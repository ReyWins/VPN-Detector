# VPN DNS Diagnostic Tool (PowerShell) — v2.3

A Windows PowerShell, menu-driven utility for diagnosing and managing VPN DNS configuration on Windows endpoints.  
It validates the VPN profile name (via `Get-VpnConnection` and `rasphone.pbk`) before proceeding, caches user inputs for reuse throughout the session, and provides one-click actions for DNS checks, DNS cache/registration operations, connectivity tests, interface metric changes, and a comprehensive exportable diagnostic report.

> Author: Alexander Reyes (adjusted by Chip, ChatGPT 4.1, 5.0).  
> Script: `DNS-VPN-Diagnostics.ps1` (v2.3)

---

## Table of Contents

- [Features](#features)  
- [Requirements](#requirements)  
- [Installation](#installation)  
- [Usage](#usage)  
  - [Interactive Menu](#interactive-menu)  
  - [Parameters](#parameters)  
  - [Examples](#examples)  
- [Use Case: Quick workflow while connected to VPN](#use-case-quick-workflow-while-connected-to-vpn)  
- [Menu Reference (1–19)](#menu-reference-1–19)  
- [Diagnostics Export](#diagnostics-export)  
- [Permissions & Safety](#permissions--safety)  
- [Compatibility](#compatibility)  
- [Troubleshooting](#troubleshooting)  
- [Known Limitations / Notes](#known-limitations--notes)  
- [Changelog](#changelog)  
- [Contributing](#contributing)  
- [License](#license)

---

## Features

- **VPN profile validation (3 attempts):**  
  Confirms the VPN profile exists using:
  - `Get-VpnConnection -Name` (user scope),
  - `Get-VpnConnection -AllUserConnection -Name` (machine scope),
  - and a fallback scan of `rasphone.pbk` files (user & all-users).

- **Input caching:**  
  Prompts once, then caches:
  - `VPN Profile Name`  
  - `Expected VPN DNS`  
  - `Desired Interface Metric` (optional - this will set what you want your interface to be versus what the current metric is).

- **Menu-driven operations:**  
  Quick views of DNS status and interface metric, bulk adapter DNS listings, DNS suffix views, DNS cache flush, registration, targeted A-record lookups against the VPN DNS, UDP/53 tests, temporary DNS set/reset, metric updates, and a full diagnostics export.

- **Exportable diagnostic report:**  
  One command collects, timestamps, and writes a detailed text report to a log folder.

- **Designed for enterprise use:**  
  All primary actions are idempotent and explicit, with confirmation prompts for changes.

- **Optional auto-elevation block:**  
  Commented code is included to relaunch with admin rights automatically if desired.

---

## Requirements

- **OS:** Windows 10 / Windows 11 (or Windows Server with the Windows VPN client components installed)  
- **PowerShell:** 5.1 or 7+ recommended  
- **Privileges:** Many change operations require **Administrator** (see Permissions & Safety)  
- **VPN profile:** Built-in Windows VPN profile present on the machine (or compatible adapter alias)

---

## Installation
⚠️ Warning: If you directly download the Powershell script it may trigger a false positive. This is due to the code not being digitally signed yet.
    This will be addressed in our next update.
1. Copy the script to a folder, e.g. `C:\VPN\DNS-VPN-Diagnostics.ps1`.  
2. (Optional) Create the log directory (default: `C:\VPN\Logs`) or allow the tool to create it when exporting.  
3. If you always want elevated execution, uncomment the “Auto-elevate to Admin” block near the top of the script.

---

## Usage

### Interactive Menu
💡 Protip: Make sure you're connected to your VPN prior to running the script.
Open PowerShell (Run as Administrator for full functionality) and run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\VPN\DNS-VPN-Diagnostics.ps1"
```

On first run you’ll be prompted for:
-**Auto Detects Connected VPN**
- **VPN Profile Name** (validated, 3 attempts)
- **Expected VPN DNS** (e.g., `10.0.0.1`)
- **Desired Interface Metric** (optional; number or blank)

These are cached for the session and can be reviewed/changed with menu option **17**.

---

### Parameters

You can pre-seed values to skip prompts:

```powershell
.\DNS-VPN-Diagnostics.ps1 `
  -vpnName "Your VPN Name" `
  -expectedVpnDns "10.0.0.1" `
  -desiredMetric "5" `
  -LogDir "C:\VPN\Logs"
```

- `-vpnName` *(string)* — VPN connection/profile name; validated before continuing.  
- `-expectedVpnDns` *(string)* — IPv4 address you expect the VPN adapter to have as DNS.  
- `-desiredMetric` *(string)* — Optional; numeric only. Leave blank to skip.  
- `-LogDir` *(string)* — Folder for diagnostics export (default `C:\VPN\Logs`).

---

### Examples

Interactive (prompted):

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\VPN\DNS-VPN-Diagnostics.ps1"
```

Fully parameterized (non-interactive prompts):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\VPN\DNS-VPN-Diagnostics.ps1" `
  -vpnName "Your-VPN-Name" `
  -expectedVpnDns "10.0.0.1" `
  -desiredMetric "5"
```

---

## Use Case: Quick workflow while connected to VPN

Scenario: You’re connected to the corporate VPN (IKEv2) and internal resources aren’t resolving.

Steps:
1. Connect to your VPN as usual (IKEv2 in this example).  
2. Launch the script (preferably as Administrator).  
3. Provide or confirm your VPN profile name and the expected DNS server IP when prompted (one-time per session).  
4. From the menu:
   - Choose **1** to confirm what DNS the VPN adapter currently has, the interface metric, and whether it matches your expected DNS.  
   - Choose **7** to test DNS resolution for an internal hostname using the VPN DNS server directly (helps determine if DNS or connectivity is at fault).  
   - If DNS is incorrect, choose **12** to temporarily set the VPN DNS to the expected value (requires admin). Re-run **1** or **7** to confirm.
   - If the adapter metric is wrong and you want traffic to prefer the VPN, set **15** (requires admin) with a previously cached desired metric.
   - Use **16** to export a full diagnostic report to `$LogDir` and attach it to an incident ticket if escalation is needed.
5. Press any key to return to the menu, or choose **18** to exit.

This flow helps quickly isolate whether DNS settings, reachability (ICMP/UDP), or the adapter metric are causing the failure.

---

## Menu Reference (1–19)

| #  | Action |
|----|--------|
| 1  | Show VPN DNS & interface metric (quick check) for the cached VPN adapter; indicates whether current DNS contains the expected DNS. |
| 2  | Show DNS servers for **all** adapters (`Get-DnsClientServerAddress`). |
| 3  | Show DNS client config for VPN (includes `RegisterThisConnectionsAddress`, suffix settings). |
| 4  | Show **full** DNS client details for the VPN adapter. |
| 5  | Show DNS suffix for all adapters. |
| 6  | Show interface metrics (all) sorted by metric (IPv4). |
| 7  | Test DNS resolution via **VPN DNS** (prompt for hostname; uses the first DNS server bound to the VPN adapter). |
| 8  | Flush local DNS cache (`Clear-DnsClientCache`). |
| 9  | Force DNS registration (`ipconfig /registerdns`). |
| 10 | Show interface metrics (all) sorted by metric (duplicate convenience). |
| 11 | Test connectivity to **Expected VPN DNS** (ICMP + UDP/53). |
| 12 | **Temporarily** set VPN DNS to the **Expected DNS** (overwrites current IPv4 DNS on that adapter). |
| 13 | Set `RegisterThisConnectionsAddress = TRUE` on the VPN adapter. |
| 14 | Reset VPN DNS to **DHCP/Automatic** (clears static entries on the VPN adapter). |
| 15 | Apply **Desired Interface Metric** to the VPN adapter (`Set-NetIPInterface`). |
| 16 | Export full DNS/VPN diagnostic report to a timestamped text file under `LogDir`. |
| 17 | Review / Change cached inputs (VPN Profile, Expected DNS, Desired Metric). |
| 18 | Exit the program. |
| 19 | Open the project owner’s GitHub profile in the default browser. |

---

## Diagnostics Export

- **Command:** Menu option **16**  
- **Output path:** `<LogDir>\vpn-dns-report_YYYYMMDD_HHMMSS.txt` (default `C:\VPN\Logs`)  
- **Includes:**
  - Quick VPN DNS vs expected DNS check and metric
  - DNS servers for all adapters
  - DNS client config for VPN adapter
  - Full DNS client details for VPN adapter
  - DNS suffix list for all adapters
  - Interface metrics (IPv4)
  - ICMP and UDP/53 tests to the expected VPN DNS
 - **Diagnostic Output Example**

```powershell
VPN DNS Diagnostic Report
Generated:  2025-08-15 20:00:15
Host:       HOST-9A1F
User:       User
VPN Profile: VPN-7B2
Expected DNS: 10.99.88.77
Desired Metric: <not set>
--------------------------------------------------------------------------------

### VPN DNS & Metric (Quick Check)
------------------------------------------------------------

InterfaceAlias DnsServers InterfaceMetric ExpectedVpnDNS MatchesExpected
-------------- ---------- --------------- -------------- ---------------
VPN-7B2        10.99.88.77              5 10.99.88.77               True

### DNS Servers for ALL Adapters
------------------------------------------------------------

InterfaceAlias               ServerAddresses                          
--------------               ---------------                          
Internal                     {}                                       
VPN-7B2                      {10.99.88.77}                            
Tailscale                    {}                                       
Wi-Fi                        {10.172.200.5, 10.8.4.33, 10.8.4.44, 10.8.4.45}
Local Area Connection* 1     {}                                       
Local Area Connection* 2     {}                                       
External                     {192.168.101.42}                         
Bluetooth Network Connection {}                                       
Loopback Pseudo-Interface 1  {}

### DNS Client Config for VPN
------------------------------------------------------------

InterfaceAlias InterfaceIndex RegisterThisConnectionsAddress UseSuffixWhenRegistering ConnectionSpecificSuffix
-------------- -------------- ------------------------------ ------------------------ ------------------------
VPN-7B2               56                          False                    False example.local

### Full VPN Adapter Details
------------------------------------------------------------


Suffix                             : example.local
SuffixSearchList                   : {}
Caption                            : 
Description                        : 
ElementName                        : 
InstanceID                         : 
CommunicationStatus                : 
DetailedStatus                     : 
HealthState                        : 
InstallDate                        : 
Name                               : 56
OperatingStatus                    : 
OperationalStatus                  : 
PrimaryStatus                      : 
Status                             : 
StatusDescriptions                 : 
AvailableRequestedStates           : 
EnabledDefault                     : 2
EnabledState                       : 
OtherEnabledState                  : 
RequestedState                     : 12
TimeOfLastStateChange              : 
TransitioningToState               : 12
CreationClassName                  : 
SystemCreationClassName            : 
SystemName                         : 
NameFormat                         : 
OtherTypeDescription               : 
ProtocolIFType                     : 
ProtocolType                       : 
DHCPOptionsToUse                   : 
Hostname                           : HOST-9A1F
ConnectionSpecificSuffix           : example.local
ConnectionSpecificSuffixSearchList : {}
InterfaceAlias                     : VPN-7B2
InterfaceIndex                     : 56
RegisterThisConnectionsAddress     : False
UseSuffixWhenRegistering           : False
PSComputerName                     : 
CimClass                           : ROOT/StandardCimv2:MSFT_DNSClient
CimInstanceProperties              : {Caption, Description, ElementName, InstanceID...}
CimSystemProperties                : Microsoft.Management.Infrastructure.CimSystemProperties

### DNS Suffix for ALL Adapters
------------------------------------------------------------

InterfaceAlias               ConnectionSpecificSuffix
--------------               ------------------------
Internal                                             
VPN-7B2                      example.local           
Tailscale                    example.ts.test       
Wi-Fi                        localdomain              
Local Area Connection* 1                             
Local Area Connection* 2                             
External                                             
Bluetooth Network Connection                          
Loopback Pseudo-Interface 1

### Interface Metrics (All)
------------------------------------------------------------

InterfaceAlias               InterfaceIndex      NlMtu     Dhcp ConnectionState InterfaceMetric
--------------               --------------      -----     ---- --------------- ---------------
VPN-7B2                             56       1360 Disabled       Connected               5
Internal                                 11       1500 Disabled    Disconnected               5
Tailscale                                 8       1280 Disabled       Connected               5
Local Area Connection* 1                 19       1500  Enabled    Disconnected              25
Local Area Connection* 2                 15       1500  Enabled    Disconnected              25
Wi-Fi                                    13       1500  Enabled    Disconnected              25
External                                  2       1460 Disabled       Connected              35
Bluetooth Network Connection             16       1500  Enabled    Disconnected              65
Loopback Pseudo-Interface 1               1 4294967295 Disabled       Connected              75

### Connectivity to Expected VPN DNS (ICMP + UDP/53)
------------------------------------------------------------
ERROR: A parameter cannot be found that matches parameter name 'Udp'.
(Note: This Error will occurr if you have ping disbaled via firewall rules. This is expected.).

```

---

## Permissions & Safety

- Viewing data: works as a standard user.  
- **Administrator** is required for:
  - Changing DNS on the VPN adapter (setting or resetting static DNS) — menu **12** & **14**.  
  - Enabling `RegisterThisConnectionsAddress` — menu **13**.  
  - Changing interface metric — menu **15**.  
  - Running `ipconfig /registerdns` may require elevation depending on system policy.  

The script includes an optional auto-elevation block (commented). If you enable it, the script will attempt to relaunch itself with elevated privileges.

---

## Compatibility

| Platform / Component | Status | Notes |
|----------------------|--------:|-------|
| Windows 11 (x64)     | ✅ Tested | Works with PowerShell 5.1+ and 7+. |
| Windows 10 (x64)     | ✅ Tested | Works with PowerShell 5.1+ and 7+. |
| Windows Server       | ✅ Partial | Works if Windows VPN client components/cmdlets are present. |
| CPU / Arch: Intel i5/i7 (64-bit) | ✅ Tested | Script tested on an Intel i7 64-bit machine (development/test environment). |
| CPU / Arch: ARM (Windows on ARM) | ⚠️ Limited / Untested | The script **may** run under PowerShell 7 on Windows on ARM; however some modules/cmdlets (particularly `Get-VpnConnection` or vendor drivers) may behave differently. Not verified in the test environment — use with care. |
| VPN Type: IKEv2      | ✅ Tested | Script tested against IKEv2 connections (profile and DNS behaviors tested). |
| VPN Types: SSTP/L2TP/PPTP | ✅ Likely | Basic adapter and DNS cmdlets are used; behavior may vary by client. |
| VPN Types: Azure VPN Client | ❌ Not Compatible | This script was created for Windows built in VPN structure. You can try to use Azure VPN Client with this script, but it is currently unsupported.  |

> If you test on Windows on ARM or other unusual configurations, please file an issue and attach a diagnostics export (menu 16) so we can improve coverage.

---

## Troubleshooting

- **“VPN profile not found” on launch**  
  - Make sure you're connected to your VPN before running the script. This script has an VPN auto detection that should automatically detect your VPN while connected.
  - Ensure the VPN profile name matches exactly. The validator checks `Get-VpnConnection -Name` (user & alluser) and `rasphone.pbk`. If your VPN is a vendor client that doesn’t expose a Windows profile, use the adapter alias shown by `Get-NetAdapter` and enter that.

- **“No matching MSFT_DNSClientServerAddress objects”**  
  - This typically means the interface alias does not have IPv4 DNS server entries (VPN may be disconnected). Use the script’s detection (candidate list) to confirm aliases and ensure the VPN is connected.

- **Permissions / Access Denied**  
  - Rerun PowerShell as Administrator or enable the auto-elevate block near the top of the script.

- **Changes are reverted on reconnect**  
  - Some VPN clients reapply DNS on reconnection. Use the script to diagnose and re-apply as needed, or configure the client/provider side if persistent behavior is required.

---

## Known Limitations / Notes

- Windows-only — relies on built-in Windows networking cmdlets.  
- Menu items **6** and **10** both show interface metrics (intentional convenience duplicate).  
- TEMP Set VPN DNS (menu **12**) sets a single DNS entry; add secondaries manually if required.  
- The script does not persist changes across VPN reconnects — it is an operator tool for ad-hoc diagnostics and changes.  
- Interface alias is assumed to match the VPN profile name for built-in Windows VPN profiles.

---

## Changelog

### v2.3
- Added VPN profile validation (user & machine scope) and rasphone.pbk fallback with up to 3 attempts.  
- Input caching for VPN name, expected DNS, and desired metric.  
- Menu rework and expanded diagnostics export.  
- Added full diagnostics export to timestamped text file under `LogDir`.  
- Added safe DNS getter to avoid CIM errors when VPN adapters are disconnected.

---

## Contributing

Issues and pull requests welcome. When filing issues, include:
- Windows version and PowerShell version (`$PSVersionTable` output).  
- VPN type (IKEv2/SSTP/L2TP/etc.) and vendor if non-built-in.  
- Diagnostics export file generated with **menu 16** (redact private IPs if necessary).

---

## License

MIT License

Copyright © 2025 Reywins

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
