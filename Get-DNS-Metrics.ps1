# DNS / VPN Diagnostics Menu Tool
# Version 2.3 (VPN name validation via rasphone/rasdial; 3 retries)
# Author: Alexander Reyes (adjusted by Chip)

<#  --- Optional: Auto-elevate to Admin on launch ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Requesting Administrator privileges..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = 'runas'
    try { [System.Diagnostics.Process]::Start($psi) | Out-Null } catch {
        Write-Host "User declined elevation. Exiting." -ForegroundColor Red
    }
    exit
}
#>

param(
    [string]$vpnName,           # if not provided, we will prompt and validate (3 tries)
    [string]$expectedVpnDns,    # if not provided, we will prompt
    [string]$desiredMetric,     # optional numeric string; prompt allows blank to skip
    [string]$LogDir = "C:\VPN\Logs"
)

# Console window title
try { $Host.UI.RawUI.WindowTitle = "VPN DNS Diagnostic Tool v2.3" } catch { [Console]::Title = "VPN DNS Diagnostic Tool v2.3" }

# ---------------- Safe DNS info getter (prevents CIM error) ----------------
function Try-GetVpnDnsInfo {
    param([string]$Alias)
    try {
        return Get-DnsClientServerAddress -InterfaceAlias $Alias -AddressFamily IPv4 -ErrorAction Stop
    } catch {
        # Silent fallback, but informative
        Write-Host "⚠️ Warning: No DNS info found for adapter '$Alias'. Is the VPN connected?" -ForegroundColor Yellow
        return $null
    }
}

# ---------------- ASCII header ----------------
function Get-AsciiHeader {
@"
VV     VV PPPPPP  NN   NN    DDDDD   NN   NN  SSSSS     TTTTTTT               lll 
VV     VV PP   PP NNN  NN    DD  DD  NNN  NN SS           TTT    oooo   oooo  lll 
 VV   VV  PPPPPP  NN N NN    DD   DD NN N NN  SSSSS       TTT   oo  oo oo  oo lll 
  VV VV   PP      NN  NNN    DD   DD NN  NNN      SS      TTT   oo  oo oo  oo lll 
   VVV    PP      NN   NN    DDDDDD  NN   NN  SSSSS       TTT    oooo   oooo  lll v2.3
"@
}

function Pause-AnyKey {
    Write-Host "`nPress any key to return to menu..." -ForegroundColor Yellow
    [void][System.Console]::ReadKey($true)
}

function Confirm-Action($Message) {
    $resp = Read-Host "$Message (Y/N)"
    return ($resp -match '^(?i)Y')
}

# ---------------- VPN discovery & validation ----------------

function Get-RasPhoneBookPaths {
    @(
        Join-Path $env:APPDATA     "Microsoft\Network\Connections\Pbk\rasphone.pbk"      # Current user
        Join-Path $env:PROGRAMDATA "Microsoft\Network\Connections\Pbk\rasphone.pbk"      # All users
    )
}

function Get-CandidateVpnAliases {
    <#
      Returns a collection of candidate VPN profile names / adapter aliases.
      Sources: Get-VpnConnection (AllUserConnection), rasphone.pbk sections, and net adapters with VPN-like descriptions.
    #>
    $candidates = New-Object System.Collections.Generic.List[string]

    # 1) Windows VPN connections (try AllUser first)
    try {
        $vpnCons = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue
        if (-not $vpnCons) { $vpnCons = Get-VpnConnection -ErrorAction SilentlyContinue }
        if ($vpnCons) {
            $vpnConsConnected = $vpnCons | Where-Object { $_.ConnectionStatus -eq 'Connected' } | Sort-Object Name
            $vpnConsOther     = $vpnCons | Where-Object { $_.ConnectionStatus -ne 'Connected' } | Sort-Object Name
            foreach ($c in @($vpnConsConnected + $vpnConsOther)) {
                if ($c.Name -and -not [string]::IsNullOrWhiteSpace($c.Name)) { $candidates.Add($c.Name) }
            }
        }
    } catch {}

    # 2) RAS phonebook entries
    foreach ($pbk in Get-RasPhoneBookPaths) {
        if (Test-Path -LiteralPath $pbk) {
            try {
                $lines = Get-Content -LiteralPath $pbk -ErrorAction Stop
                foreach ($line in $lines) {
                    if ($line -match '^\[(.+?)\]\s*$') { $name = $matches[1]; if ($name) { $candidates.Add($name) } }
                }
            } catch {}
        }
    }

    # 3) Network adapters that look like VPNs
    try {
        $vpnLike = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            ($_.InterfaceDescription -match 'VPN|IKEv2|L2TP|PPTP|SSTP|WAN Miniport') -or ($_.InterfaceAlias -match 'VPN|vnet|tun|tap')
        }
        foreach ($n in $vpnLike) { if ($n.InterfaceAlias) { $candidates.Add($n.InterfaceAlias) } }
    } catch {}

    # Return unique list preserving order
    $seen = @{ }
    $result = @()
    foreach ($item in $candidates) {
        if (-not $seen.ContainsKey($item)) {
            $seen[$item] = $true
            $result += $item
        }
    }
    return ,$result
}

function Test-VpnProfileExists([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }

    try { if (Get-VpnConnection -AllUserConnection -Name $Name -ErrorAction SilentlyContinue) { return $true } } catch {}
    try { if (Get-VpnConnection -Name $Name -ErrorAction SilentlyContinue) { return $true } } catch {}

    foreach ($pbk in Get-RasPhoneBookPaths) {
        if (Test-Path -LiteralPath $pbk) {
            try {
                foreach ($line in Get-Content -LiteralPath $pbk -ErrorAction Stop) {
                    if ($line.Trim() -ieq ("[{0}]" -f $Name)) { return $true }
                }
            } catch {}
        }
    }
    try { if (Get-NetAdapter -InterfaceAlias $Name -ErrorAction SilentlyContinue) { return $true } } catch {}

    return $false
}

function Detect-VpnAlias {
    # Prefer a connected vpn connection
    try {
        $connected = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue |
                     Where-Object { $_.ConnectionStatus -eq 'Connected' } |
                     Select-Object -ExpandProperty Name -First 1
        if (-not $connected) {
            $connected = Get-VpnConnection -ErrorAction SilentlyContinue |
                         Where-Object { $_.ConnectionStatus -eq 'Connected' } |
                         Select-Object -ExpandProperty Name -First 1
        }
        if ($connected) { return $connected }
    } catch {}

    # Otherwise show a short candidate list and allow pick or manual entry
    $candidates = Get-CandidateVpnAliases
    if (-not $candidates -or $candidates.Count -eq 0) { return $null }

    # If exactly one candidate, return it
    if ($candidates.Count -eq 1) { return $candidates[0] }

    # Print short list (up to 12) and allow user to choose or type
    Write-Host "`nDetected possible VPN profiles/adapters (showing top 12):" -ForegroundColor Cyan
    $i = 1
    foreach ($n in $candidates | Select-Object -Unique | Select-Object -First 12) {
        "{0,2}) {1}" -f $i, $n | Write-Host
        $i++
    }
    $pick = Read-Host "Choose 1-$($i-1) or press Enter to type a name"
    if ($pick -match '^\d+$') {
        $idx = [int]$pick
        if ($idx -ge 1 -and $idx -lt $i) {
            return ($candidates | Select-Object -Unique | Select-Object -First 12)[$idx - 1]
        }
    }
    # fallthrough: return $null to force manual entry upstream
    return $null
}

# ---------------- Inputs & caching ----------------

$global:CachedVpnName        = $null
$global:CachedExpectedVpnDns = $null
$global:CachedDesiredMetric  = $null

function Initialize-Inputs {
    # Auto-detect VPN name first (non-blocking)
    if ([string]::IsNullOrWhiteSpace($vpnName)) {
        $detected = Detect-VpnAlias
        if ($detected) {
            Write-Host "Auto-detected VPN profile/adapter: '$detected'" -ForegroundColor Green
            $vpnName = $detected
        }
    }

    # Validate or let user try up to 3 times
    $maxTries = 3
    $try = 0
    while ([string]::IsNullOrWhiteSpace($vpnName) -or -not (Test-VpnProfileExists -Name $vpnName)) {
        $try++
        if ($try -gt $maxTries) {
            Write-Host "VPN profile validation failed after $maxTries attempts. Exiting." -ForegroundColor Red
            exit 1
        }
        if (-not [string]::IsNullOrWhiteSpace($vpnName)) {
            Write-Host "VPN profile '$vpnName' not found. Attempt $try of $maxTries." -ForegroundColor Yellow
        }
        $vpnName = Read-Host "Enter VPN Profile/Adapter Name (e.g., My-VPN-Connection)"
    }

    # Expected/Current VPN DNS (required; freeform)
    if ([string]::IsNullOrWhiteSpace($expectedVpnDns)) {
        do {
            $expectedVpnDns = Read-Host "Enter Current/Expected VPN DNS (e.g., 10.0.0.1)"
            if ([string]::IsNullOrWhiteSpace($expectedVpnDns)) {
                Write-Host "Expected VPN DNS is required." -ForegroundColor Red
            }
        } while ([string]::IsNullOrWhiteSpace($expectedVpnDns))
    }

    # Desired Interface Metric (optional; numeric)
    if ($null -eq $desiredMetric) {
        $desiredMetric = Read-Host "Enter Desired Interface Metric (optional; numbers only; leave blank to skip)"
    }
    if (-not [string]::IsNullOrWhiteSpace($desiredMetric)) {
        while ($desiredMetric -notmatch '^\d+$') {
            Write-Host "Interface Metric must be numbers only (or leave blank to skip)." -ForegroundColor Red
            $desiredMetric = Read-Host "Desired Interface Metric (optional; numbers only; leave blank to skip)"
            if ([string]::IsNullOrWhiteSpace($desiredMetric)) { break }
        }
    }

    # Cache
    $global:CachedVpnName        = $vpnName
    $global:CachedExpectedVpnDns = $expectedVpnDns
    $global:CachedDesiredMetric  = if ([string]::IsNullOrWhiteSpace($desiredMetric)) { $null } else { $desiredMetric }
}

function ReviewOrChange-Inputs {
    Write-Host "`nCurrent cached inputs:" -ForegroundColor Cyan
    [PSCustomObject]@{
        VpnProfileName         = $global:CachedVpnName
        ExpectedVpnDns         = $global:CachedExpectedVpnDns
        DesiredInterfaceMetric = $(if ($global:CachedDesiredMetric) { $global:CachedDesiredMetric } else { "<not set>" })
    } | Format-Table -AutoSize

    if (Confirm-Action "Change these values?") {
        # VPN name
        $tmpVpn = Read-Host "Enter VPN Profile Name [currently '$($global:CachedVpnName)'] (leave blank to keep)"
        if (-not [string]::IsNullOrWhiteSpace($tmpVpn)) {
            $maxTries = 3
            for ($attempt = 1; $attempt -le $maxTries; $attempt++) {
                if (Test-VpnProfileExists -Name $tmpVpn) { $global:CachedVpnName = $tmpVpn; break }
                else {
                    $left = $maxTries - $attempt
                    if ($left -gt 0) {
                        Write-Host "VPN profile '$tmpVpn' not found (rasphone/rasdial). Attempts left: $left" -ForegroundColor Red
                        $tmpVpn = Read-Host "Re-enter VPN Profile Name (or blank to cancel change)"
                        if ([string]::IsNullOrWhiteSpace($tmpVpn)) { break }
                    } else {
                        Write-Host "Validation failed. Keeping previous VPN name." -ForegroundColor Yellow
                    }
                }
            }
        }

        # Expected DNS
        $tmpDns = Read-Host "Enter Expected VPN DNS [currently '$($global:CachedExpectedVpnDns)'] (leave blank to keep)"
        if (-not [string]::IsNullOrWhiteSpace($tmpDns)) { $global:CachedExpectedVpnDns = $tmpDns }

        # Metric
        $tmpMetric = Read-Host "Enter Desired Interface Metric [currently '$($global:CachedDesiredMetric)'] (optional; numbers only; blank to clear)"
        if ([string]::IsNullOrWhiteSpace($tmpMetric)) {
            $global:CachedDesiredMetric = $null
        } elseif ($tmpMetric -match '^\d+$') {
            $global:CachedDesiredMetric = $tmpMetric
        } else {
            Write-Host "Ignored: metric must be numbers only. Keeping existing value." -ForegroundColor Yellow
        }

        Write-Host "`nUpdated cached inputs:" -ForegroundColor Green
        [PSCustomObject]@{
            VpnProfileName         = $global:CachedVpnName
            ExpectedVpnDns         = $global:CachedExpectedVpnDns
            DesiredInterfaceMetric = $(if ($global:CachedDesiredMetric) { $global:CachedDesiredMetric } else { "<not set>" })
        } | Format-Table -AutoSize
    }
    Pause-AnyKey
}

# ---------------- Utility: Logging ----------------

function Ensure-LogDir {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
}
function New-LogPath {
    Ensure-LogDir
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Join-Path $LogDir ("vpn-dns-report_{0}.txt" -f $stamp)
}

# ---------------- UI ----------------
function Show-Header {
    Clear-Host
    Write-Host (Get-AsciiHeader) -ForegroundColor Cyan
    Write-Host "VPN DNS Diagnostic Tool v2.3" -ForegroundColor Gray
    Write-Host ("VPN Profile: {0}" -f $global:CachedVpnName)
    Write-Host ("Expected DNS: {0}" -f $global:CachedExpectedVpnDns)
    Write-Host ("Desired Metric: {0}" -f ($(if ($global:CachedDesiredMetric) { $global:CachedDesiredMetric } else { "<not set>" })))
    try {
        $dnsInfo = Try-GetVpnDnsInfo -Alias $global:CachedVpnName
        if ($dnsInfo) {
            # metric retrieval could still throw; guard it
            try {
                $metric  = (Get-NetIPInterface -InterfaceAlias $global:CachedVpnName -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric
                Write-Host ("Current VPN DNS: " + ($dnsInfo.ServerAddresses -join ", "))
                Write-Host ("Current VPN Interface Metric: {0}" -f $metric)
            } catch {
                Write-Host ("Current VPN DNS: " + ($dnsInfo.ServerAddresses -join ", "))
                Write-Host "Current VPN Interface Metric: <unavailable>" -ForegroundColor DarkYellow
            }
        }
    } catch {
        Write-Host "Unable to read current VPN adapter details: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    Write-Host ("-" * 80) -ForegroundColor DarkGray
    Write-Host
}

function Menu {
    Write-Host "----DNS Settings----" -ForegroundColor Cyan
    Write-Host " 1) Show VPN DNS & interface metric (quick check)"
    Write-Host " 2) Show DNS servers for ALL adapters"
    Write-Host " 3) Show DNS client config for VPN (incl. RegisterThisConnectionsAddress)"
    Write-Host " 4) Show FULL details for VPN adapter"
    Write-Host " 5) Show DNS suffix for ALL adapters"
    Write-Host " 6) Show interface metrics (all) sorted by metric"
    Write-Host ""
    Write-Host "----DNS Tools----" -ForegroundColor Cyan
    Write-Host " 7) Test DNS resolution via VPN DNS (prompt for hostname)"
    Write-Host " 8) Flush local DNS cache"
    Write-Host " 9) Force DNS registration (ipconfig /registerdns)"
    Write-Host "10) Show interface metrics (all) sorted by metric"
    Write-Host "11) Test connectivity to Expected VPN DNS ($($global:CachedExpectedVpnDns)) & UDP 53"
    Write-Host "12) TEMP set VPN DNS to Expected DNS ($($global:CachedExpectedVpnDns))"
    Write-Host "13) Set RegisterThisConnectionsAddress=TRUE for VPN"
    Write-Host "14) Reset VPN DNS to DHCP/Automatic"
    Write-Host "15) Apply Desired Interface Metric to VPN adapter"
    Write-Host ""
    Write-Host "----DNS Diagnosis----" -ForegroundColor Cyan
    Write-Host "16) Export full DNS/VPN diagnostic report to timestamped log"
    Write-Host "17) Review/Change cached inputs (VPN Profile, Expected DNS, Desired Metric)"
    Write-Host ""
    Write-Host "----Exit Powershell Program-----" -ForegroundColor Yellow
    Write-Host "18) Exit"
    Write-Host ""
    Write-Host "----Visit Us----" -ForegroundColor Magenta
    Write-Host "19) Github"
}

# ---------------- Startup ----------------
Initialize-Inputs

# ---------------- Main loop ----------------
while ($true) {
    Show-Header
    Menu
    $choice = Read-Host "`nSelect 1-19"

    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt 19) {
        Write-Host "PLEASE CHOOSE # 1-19" -ForegroundColor Red
        Start-Sleep -Seconds 1.2
        continue
    }

    # Clear the screen and re-show header for the selected action (menu will not be visible during action)
    Clear-Host
    Show-Header

    switch ([int]$choice) {
        1 {
            try {
                $dnsInfo = Try-GetVpnDnsInfo -Alias $global:CachedVpnName
                if (-not $dnsInfo) { Pause-AnyKey; break }
                try { $metric  = (Get-NetIPInterface -InterfaceAlias $global:CachedVpnName -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric } catch { $metric = "<unavailable>" }
                [PSCustomObject]@{
                    InterfaceAlias   = $global:CachedVpnName
                    DnsServers       = $dnsInfo.ServerAddresses -join ", "
                    InterfaceMetric  = $metric
                    ExpectedVpnDNS   = $global:CachedExpectedVpnDns
                    MatchesExpected  = ($dnsInfo.ServerAddresses -contains $global:CachedExpectedVpnDns)
                } | Format-Table -AutoSize
            } catch {
                Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        2 {
            try {
                Get-DnsClientServerAddress -AddressFamily IPv4 |
                    Select-Object InterfaceAlias, ServerAddresses |
                    Format-Table -AutoSize
            } catch {
                Write-Host "Failed to list DNS servers: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        3 {
            try {
                Get-DnsClient -InterfaceAlias $global:CachedVpnName |
                    Select-Object InterfaceAlias, InterfaceIndex, RegisterThisConnectionsAddress, UseSuffixWhenRegistering, ConnectionSpecificSuffix |
                    Format-Table -AutoSize
            } catch {
                Write-Host "Failed to get DNS client config: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        4 {
            try {
                Get-DnsClient -InterfaceAlias $global:CachedVpnName | Format-List *
            } catch {
                Write-Host "Failed to get full VPN adapter details: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        5 {
            try {
                Get-DnsClient | Select-Object InterfaceAlias, ConnectionSpecificSuffix | Format-Table -AutoSize
            } catch {
                Write-Host "Failed to get DNS suffixes: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        6 {
            try {
                Get-NetIPInterface -AddressFamily IPv4 |
                    Select-Object InterfaceAlias, InterfaceIndex, NlMtu, Dhcp, ConnectionState, InterfaceMetric |
                    Sort-Object InterfaceMetric, InterfaceAlias |
                    Format-Table -AutoSize
            } catch {
                Write-Host "Failed to get interface metrics: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        7 {
            $hostName = Read-Host "Enter hostname to resolve (e.g., intranet.contonso.com or  www.microsoft.com)"
            if ([string]::IsNullOrWhiteSpace($hostName)) {
                Write-Host "No hostname entered." -ForegroundColor Yellow
                Pause-AnyKey
                break
            }
            try {
                $dnsInfo = Try-GetVpnDnsInfo -Alias $global:CachedVpnName
                if (-not $dnsInfo) { Pause-AnyKey; break }
                $server = $dnsInfo.ServerAddresses | Select-Object -First 1
                if (-not $server) { throw "No DNS server found on $($global:CachedVpnName)." }
                Write-Host "Querying $hostName using server $server ..." -ForegroundColor Cyan
                Resolve-DnsName -Name $hostName -Server $server -Type A -ErrorAction Stop | Format-Table -AutoSize
            } catch {
                Write-Host "DNS resolution failed: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        8 {
            try {
                Clear-DnsClientCache
                Write-Host "Local DNS cache cleared." -ForegroundColor Green
            } catch {
                Write-Host "Failed to clear cache: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        9 {
            try {
                Write-Host "Forcing DNS registration (ipconfig /registerdns)..." -ForegroundColor Cyan
                Start-Process -FilePath ipconfig.exe -ArgumentList "/registerdns" -NoNewWindow -Wait
                Write-Host "Registration attempted." -ForegroundColor Green
            } catch {
                Write-Host "Failed to run ipconfig: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        10 {
            try {
                Get-NetIPInterface -AddressFamily IPv4 |
                    Select-Object InterfaceAlias, InterfaceIndex, NlMtu, Dhcp, ConnectionState, InterfaceMetric |
                    Sort-Object InterfaceMetric, InterfaceAlias |
                    Format-Table -AutoSize
            } catch {
                Write-Host "Failed to show interface metrics: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        11 {
            try {
                Write-Host "Pinging $($global:CachedExpectedVpnDns) ..." -ForegroundColor Cyan
                Test-NetConnection -ComputerName $global:CachedExpectedVpnDns -InformationLevel Detailed | Format-List *
            } catch {
                Write-Host "Basic ping failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
            try {
                Write-Host "`nTesting UDP/53 to $($global:CachedExpectedVpnDns) ..." -ForegroundColor Cyan
                Test-NetConnection -ComputerName $global:CachedExpectedVpnDns -Port 53 -Udp -InformationLevel Detailed | Format-List *
            } catch {
                Write-Host "UDP/53 test failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
            }
            Pause-AnyKey
        }
        12 {
            if (Confirm-Action "TEMPORARILY set VPN DNS to $($global:CachedExpectedVpnDns) for $($global:CachedVpnName)? (Overwrites current IPv4 DNS)") {
                try {
                    Set-DnsClientServerAddress -InterfaceAlias $global:CachedVpnName -ServerAddresses $global:CachedExpectedVpnDns -ErrorAction Stop
                    Write-Host "VPN DNS set to $($global:CachedExpectedVpnDns)." -ForegroundColor Green
                    Get-DnsClientServerAddress -InterfaceAlias $global:CachedVpnName -AddressFamily IPv4 |
                        Select-Object InterfaceAlias, ServerAddresses | Format-Table -AutoSize
                } catch {
                    Write-Host "Failed to set VPN DNS: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "No change made." -ForegroundColor Yellow
            }
            Pause-AnyKey
        }
        13 {
            if (Confirm-Action "Set RegisterThisConnectionsAddress=TRUE on $($global:CachedVpnName)?") {
                try {
                    Set-DnsClient -InterfaceAlias $global:CachedVpnName -RegisterThisConnectionsAddress $true -ErrorAction Stop
                    Write-Host "RegisterThisConnectionsAddress enabled for $($global:CachedVpnName)." -ForegroundColor Green
                    Get-DnsClient -InterfaceAlias $global:CachedVpnName |
                        Select-Object InterfaceAlias, RegisterThisConnectionsAddress | Format-Table -AutoSize
                } catch {
                    Write-Host "Failed to set value: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "No change made." -ForegroundColor Yellow
            }
            Pause-AnyKey
        }
        14 {
            if (Confirm-Action "RESET VPN DNS on $($global:CachedVpnName) to DHCP/Automatic? (Clears static DNS)") {
                try {
                    Set-DnsClientServerAddress -InterfaceAlias $global:CachedVpnName -ResetServerAddresses -ErrorAction Stop
                    Write-Host "VPN DNS reset to DHCP/Automatic." -ForegroundColor Green
                    Get-DnsClientServerAddress -InterfaceAlias $global:CachedVpnName -AddressFamily IPv4 |
                        Select-Object InterfaceAlias, ServerAddresses | Format-Table -AutoSize
                } catch {
                    Write-Host "Failed to reset DNS: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "No change made." -ForegroundColor Yellow
            }
            Pause-AnyKey
        }
        15 {
            if (-not $global:CachedDesiredMetric) {
                Write-Host "No Desired Interface Metric set. Choose option 17 to set one first." -ForegroundColor Yellow
                Pause-AnyKey
                break
            }
            if (Confirm-Action "Apply Desired Interface Metric ($($global:CachedDesiredMetric)) to $($global:CachedVpnName)?") {
                try {
                    Set-NetIPInterface -InterfaceAlias $global:CachedVpnName -InterfaceMetric ([int]$global:CachedDesiredMetric) -ErrorAction Stop
                    Write-Host "Interface metric set to $($global:CachedDesiredMetric) on $($global:CachedVpnName)." -ForegroundColor Green
                    Get-NetIPInterface -InterfaceAlias $global:CachedVpnName -AddressFamily IPv4 |
                        Select-Object InterfaceAlias, InterfaceMetric | Format-Table -AutoSize
                } catch {
                    Write-Host "Failed to set interface metric: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "No change made." -ForegroundColor Yellow
            }
            Pause-AnyKey
        }
        16 {
            # Export diagnostic report
            try {
                $logPath = New-LogPath
                Write-Host "Collecting diagnostics and exporting to:`n$logPath" -ForegroundColor Cyan

                $report = New-Object System.Collections.Generic.List[string]
                $report.Add("VPN DNS Diagnostic Report")
                $report.Add("Generated:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
                $report.Add("Host:       $env:COMPUTERNAME")
                $report.Add("User:       $env:USERNAME")
                $report.Add("VPN Profile: $($global:CachedVpnName)")
                $report.Add("Expected DNS: $($global:CachedExpectedVpnDns)")
                $report.Add("Desired Metric: $( if ($global:CachedDesiredMetric) { $global:CachedDesiredMetric } else { '<not set>' } )")
                $report.Add(("-" * 80))

                function Add-Section($title, $scriptBlock) {
                    $report.Add("")
                    $report.Add("### $title")
                    $report.Add(("-" * 60))
                    try {
                        $out = & $scriptBlock | Out-String
                        if ([string]::IsNullOrWhiteSpace($out)) { $out = "<no output>" }
                        $report.Add($out.TrimEnd())
                    } catch {
                        $report.Add("ERROR: $($_.Exception.Message)")
                    }
                }

                Add-Section "VPN DNS & Metric (Quick Check)" {
                    $dnsInfo = Try-GetVpnDnsInfo -Alias $global:CachedVpnName
                    if ($dnsInfo) {
                        try { $metric  = (Get-NetIPInterface -InterfaceAlias $global:CachedVpnName -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric } catch { $metric = "<unavailable>" }
                        [PSCustomObject]@{
                            InterfaceAlias   = $global:CachedVpnName
                            DnsServers       = $dnsInfo.ServerAddresses -join ", "
                            InterfaceMetric  = $metric
                            ExpectedVpnDNS   = $global:CachedExpectedVpnDns
                            MatchesExpected  = ($dnsInfo.ServerAddresses -contains $global:CachedExpectedVpnDns)
                        } | Format-Table -AutoSize
                    } else { "<no dns info>" }
                }

                Add-Section "DNS Servers for ALL Adapters" {
                    Get-DnsClientServerAddress -AddressFamily IPv4 |
                        Select-Object InterfaceAlias, ServerAddresses | Format-Table -AutoSize
                }

                Add-Section "DNS Client Config for VPN" {
                    Get-DnsClient -InterfaceAlias $global:CachedVpnName |
                        Select-Object InterfaceAlias, InterfaceIndex, RegisterThisConnectionsAddress, UseSuffixWhenRegistering, ConnectionSpecificSuffix |
                        Format-Table -AutoSize
                }

                Add-Section "Full VPN Adapter Details" {
                    Get-DnsClient -InterfaceAlias $global:CachedVpnName | Format-List *
                }

                Add-Section "DNS Suffix for ALL Adapters" {
                    Get-DnsClient | Select-Object InterfaceAlias, ConnectionSpecificSuffix | Format-Table -AutoSize
                }

                Add-Section "Interface Metrics (All)" {
                    Get-NetIPInterface -AddressFamily IPv4 |
                        Select-Object InterfaceAlias, InterfaceIndex, NlMtu, Dhcp, ConnectionState, InterfaceMetric |
                        Sort-Object InterfaceMetric, InterfaceAlias |
                        Format-Table -AutoSize
                }

                Add-Section "Connectivity to Expected VPN DNS (ICMP + UDP/53)" {
                    $icmp = (Test-NetConnection -ComputerName $global:CachedExpectedVpnDns -InformationLevel Detailed | Out-String)
                    $udp  = (Test-NetConnection -ComputerName $global:CachedExpectedVpnDns -Port 53 -Udp -InformationLevel Detailed | Out-String)
                    $icmp + "`r`n" + $udp
                }

                $reportText = ($report -join "`r`n")
                Set-Content -LiteralPath $logPath -Value $reportText -Encoding UTF8

                Write-Host "Export complete." -ForegroundColor Green
                Write-Host "Saved to: $logPath" -ForegroundColor Gray
            } catch {
                Write-Host "Failed to export diagnostics: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-AnyKey
        }
        17 {
            ReviewOrChange-Inputs
        }
        18 {
            Write-Host "`nExiting program..." -ForegroundColor Cyan
            break
        }
        19 {
            Start-Process "https://github.com/reywins"
            Pause-AnyKey
        }
        default {
            Write-Host "Invalid selection." -ForegroundColor Red
            Pause-AnyKey
        }
    }

    # Loop termination check (user chose 18)
    if ([int]$choice -eq 18) { break }
}
