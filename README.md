# VPN DNS Diagnostic Tool (PowerShell) — v2.3

A Windows PowerShell, menu-driven utility for diagnosing and managing VPN DNS configuration on Windows endpoints.  
It validates the VPN profile name (via `Get-VpnConnection` and `rasphone.pbk`) before proceeding, caches user inputs for reuse throughout the session, and provides one-click actions for DNS checks, DNS cache/registration operations, connectivity tests, interface metric changes, and a comprehensive exportable diagnostic report.

> Author: Alexander Reyes (adjusted by Chip)  
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
  - [Task Scheduler (Run Hidden)](#task-scheduler-run-hidden)
- [Menu Reference (1–19)](#menu-reference)
- [Diagnostics Export](#diagnostics-export)
- [Permissions & Safety](#permissions--safety)
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
  - `Desired Interface Metric` (optional)

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

- **OS:** Windows 10/11 (or Windows Server with the Windows VPN client components installed)
- **PowerShell:** 5.1 or 7+
- **Privileges:**  
  - Viewing commands work as standard user.  
  - Changing DNS, toggling registration flags, and setting interface metrics require **Administrator**.
- **VPN profile:** Windows built-in VPN profile present on the machine.

---

## Installation

1. Copy the script into a secured directory, e.g. `C:\VPN\DNS-VPN-Diagnostics.ps1`.
2. (Optional) Create the log directory (default `C:\VPN\Logs`), or let the tool create it when exporting.
3. If you always want to run elevated, **uncomment** the “Auto-elevate to Admin” block near the top of the script.

---

## Usage

### Interactive Menu

Launch PowerShell **as Administrator** for full functionality, then:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\VPN\DNS-VPN-Diagnostics.ps1"
```

On first run, you’ll be prompted for:
- **VPN Profile Name** (validated, 3 tries)
- **Expected VPN DNS** (e.g., `10.15.0.4`)
- **Desired Interface Metric** (optional; number or blank)

These are cached for the current session and can be reviewed/changed via menu option **17**.

---

### Parameters

You can pre-seed values to skip prompts:

```powershell
.\DNS-VPN-Diagnostics.ps1 `
  -vpnName "ELMFS-VPN-v2" `
  -expectedVpnDns "10.15.0.4" `
  -desiredMetric "5" `
  -LogDir "C:\VPN\Logs"
```

- `-vpnName` *(string)*: VPN connection/profile name; validated before continuing.
- `-expectedVpnDns` *(string)*: The IPv4 DNS you expect on the VPN adapter.
- `-desiredMetric` *(string)*: Optional; numeric only. Leave blank to skip.
- `-LogDir` *(string)*: Folder for diagnostics export (default `C:\VPN\Logs`).

---

### Examples

Run with prompts (interactive):

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\VPN\DNS-VPN-Diagnostics.ps1"
```

Run fully parameterized:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden `
  -File "C:\VPN\DNS-VPN-Diagnostics.ps1" `
  -vpnName "ELMFS-VPN-v2" `
  -expectedVpnDns "10.15.0.4" `
  -desiredMetric "5"
```

---

### Task Scheduler (Run Hidden)

1. **Action**
   - Program/script: `powershell.exe`
   - Add arguments:  
     ```
     -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\VPN\DNS-VPN-Diagnostics.ps1" -vpnName "ELMFS-VPN-v2" -expectedVpnDns "10.15.0.4" -desiredMetric "5"
     ```
   - Start in (optional): `C:\VPN\`

2. **General**
   - Run whether user is logged on or not
   - Run with highest privileges

3. **Triggers**
   - At logon, and/or on a schedule as needed.

> Note: The tool is interactive by design; scheduled runs are most useful for quick checks or generating diagnostics with known parameters.

---

## Menu Reference

| #  | Action |
|----|--------|
| 1  | Show VPN DNS & interface metric (quick check) for the cached VPN adapter; indicates whether current DNS contains the expected DNS. |
| 2  | Show DNS servers for **all** adapters (`Get-DnsClientServerAddress`). |
| 3  | Show DNS client config for VPN (includes `RegisterThisConnectionsAddress`, suffix settings). |
| 4  | Show **full** DNS client details for the VPN adapter (`Get-DnsClient … | Format-List *`). |
| 5  | Show DNS suffix for all adapters. |
| 6  | Show interface metrics (all) sorted by metric (IPv4). |
| 7  | Test DNS resolution via **VPN DNS** (prompt for hostname; uses the first DNS server bound to the VPN adapter). |
| 8  | Flush local DNS cache (`Clear-DnsClientCache`). |
| 9  | Force DNS registration (`ipconfig /registerdns`). |
| 10 | Show interface metrics (all) sorted by metric (duplicate of #6, by design). |
| 11 | Test connectivity to **Expected VPN DNS** (ICMP + UDP/53) using `Test-NetConnection`. |
| 12 | **Temporarily** set VPN DNS to the **Expected DNS** (overwrites current IPv4 DNS on that adapter). |
| 13 | Set `RegisterThisConnectionsAddress = TRUE` on the VPN adapter. |
| 14 | Reset VPN DNS to **DHCP/Automatic** (clears static entries on the VPN adapter). |
| 15 | Apply **Desired Interface Metric** to the VPN adapter (`Set-NetIPInterface`). |
| 16 | Export full DNS/VPN diagnostic report to a timestamped text file under `LogDir`. |
| 17 | Review/Change cached inputs (VPN Profile, Expected DNS, Desired Metric). |
| 18 | Exit the program. |
| 19 | Open the project owner’s GitHub profile in the default browser. |

---

## Diagnostics Export

- **Command:** Menu option **16**
- **Output path:** `<LogDir>\vpn-dns-report_YYYYMMDD_HHMMSS.txt` (default `C:\VPN\Logs`)
- **Includes:**
  - Quick check of VPN DNS vs expected DNS and interface metric
  - DNS servers for all adapters
  - DNS client config for the VPN adapter (registration flags and suffix)
  - Full DNS client details for the VPN adapter
  - DNS suffix overview for all adapters
  - Interface metrics (all, IPv4)
  - ICMP and UDP/53 tests to the expected VPN DNS

---

## Permissions & Safety

- Viewing information generally works as standard user.
- The following operations require **Administrator**:
  - Setting DNS on the VPN adapter (menu 12 & 14)
  - Enabling `RegisterThisConnectionsAddress` (menu 13)
  - Changing the interface metric (menu 15)
  - Running `ipconfig /registerdns` (menu 9) may require elevation depending on policy
- An optional auto-elevation block is provided near the top of the script; uncomment it to always run elevated.

---

## Troubleshooting

- **“VPN profile not found” on launch**  
  Ensure the **VPN profile name** matches exactly what’s shown in Windows VPN settings. The validator checks:
  - `Get-VpnConnection -Name <name>`
  - `Get-VpnConnection -AllUserConnection -Name <name>`
  - `rasphone.pbk` files for a matching section header `[<name>]`

- **“Access denied” or “Insufficient privileges”**  
  Re-launch PowerShell **as Administrator**, or enable the auto-elevate block.

- **“Unable to read current VPN adapter details”**  
  Typically indicates the adapter is disconnected, mis-named, or the session lacks rights.

- **DNS set/reset appears to have no effect**  
  Some VPN clients or connection events can re-apply their own DNS. Use menu **12** to set, **14** to reset, and re-check with **1**.
  
- **UDP/53 tests fail while ICMP works**  
  Check firewall rules and whether the expected DNS server listens on UDP/53 from your subnet.

---

## Known Limitations / Notes

- **Windows-only** design targeting the built-in Windows VPN stack and DNS cmdlets.
- Menu **6** and **10** both show interface metrics by design (duplicated convenience).
- **TEMP Set VPN DNS (menu 12)** sets a single server (the expected DNS you provided). Add secondary DNS manually if desired.
- The tool does **not** persist configuration across VPN reconnects; it provides ad-hoc diagnostics and changes on demand.
- The **interface alias** is assumed to match the VPN profile name (standard for Windows built-in VPN connections).

---

## Changelog

### v2.3
- Added **VPN profile validation** (user/all-user `Get-VpnConnection` + `rasphone.pbk`) with up to **3 attempts**.
- Implemented **input caching** for VPN Name, Expected VPN DNS, and Desired Metric.
- New menu structure with explicit diagnostic, tools, and export sections.
- Added **full diagnostics export** to timestamped text file under `LogDir`.
- Confirmation prompts for all changing operations (DNS set/reset, metric, and registration flag).

---

## Contributing

Issues and PRs are welcome. Please:
- Reproduce with exact parameters and environment details.
- Attach a sanitized diagnostics export (menu 16) when relevant.

---

## License

MIT. See `LICENSE` for details.
