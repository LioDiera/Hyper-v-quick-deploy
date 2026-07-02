# Hyper-V Quick Deploy

A PowerShell module for fully unattended Windows and Ubuntu VM deployment on Hyper-V, driven by a polished terminal TUI.

## Features

- Interactive terminal UI — keyboard-driven menus, no GUI required
- Fully unattended Windows setup via auto-generated `autounattend.xml` burned to a throwaway answer ISO
- Edition picker for multi-SKU ISOs (Standard / Datacenter, Core / Desktop Experience)
- On-the-fly VM spec editing before deployment (CPU, RAM, disk, switch)
- Local `labadmin` account created alongside the built-in Administrator
- Product key management — store org/MAK keys separately from the module; GVLKs used as fallback
- Post-install key activation via `slmgr.vbs` in the specialize pass
- Domain-join, workgroup, and hybrid join-type support

## Supported OS Profiles

| Profile | Gen | Notes |
|---|---|---|
| Windows Server 2025 | 2 | Standard / Datacenter, Core / Desktop Experience |
| Windows Server 2022 | 2 | Standard / Datacenter, Core / Desktop Experience |
| Windows Server 2019 | 2 | Standard / Datacenter, Core / Desktop Experience |
| Windows Server 2016 | 2 | Standard / Datacenter, Core / Desktop Experience |
| Windows Server 2012 R2 | 1 | |
| Windows 11 | 2 | Enterprise / Pro / Education |
| Windows 10 | 2 | Enterprise / Pro / Education |
| Ubuntu Server | 2 | No answer file (manual first-boot) |

## Requirements

- Windows 10 / 11 or Windows Server 2016+ host
- Hyper-V role enabled
- PowerShell 5.1 or later
- Run as Administrator

## Quick Start

```powershell
# From the repo root (no installation needed)
.\deploy.ps1
```

On first run you will be prompted to configure:
- Default VM folder
- Default virtual switch
- ISO paths per OS profile
- Whether to auto-start VMs after creation

Configuration is saved to `$env:APPDATA\HyperVQuickDeploy\config.psd1`.

## Product Keys (Optional)

To store your own volume/MAK keys so they are applied automatically:

```powershell
Import-Module .\HyperVQuickDeploy.psm1
Edit-HVQDProductKeys
```

Keys are stored in `$env:APPDATA\HyperVQuickDeploy\keys.psd1` and never committed to the repo.

## Project Structure

```
HyperVQuickDeploy.psm1   — module entry point + TUI flow
HyperVQuickDeploy.psd1   — module manifest
deploy.ps1               — launcher (resolves paths, imports module)
lib/
  Config.ps1             — config read/write helpers
  HyperV.ps1             — VM creation helpers
  UI.ps1                 — TUI engine (ANSI, menus, progress screens)
  Unattend.ps1           — autounattend.xml generation + answer ISO creation
  Validation.ps1         — input validation helpers
profiles/
  windows-server-2025.psd1
  windows-server-2022.psd1
  ...                    — one .psd1 per supported OS
```

## Notes

- Answer ISOs and `autounattend.xml` files are excluded from the repo via `.gitignore` because they contain the VM administrator password in plaintext.
- User config (`config.psd1`) and product keys (`keys.psd1`) live in `$env:APPDATA` and are never stored in the repo.
