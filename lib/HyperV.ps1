# =============================================================================
# HyperV.ps1 — Hyper-V VM creation wrappers
# Wraps Hyper-V cmdlets in a structured, testable way.
# All memory values in profiles are in MB; this file converts to bytes for
# Set-VMMemory (which takes bytes, not MB).
# Generation-specific settings (SecureBoot, TPM) are handled here so the
# orchestrator never calls Hyper-V cmdlets directly.
# =============================================================================

# ---------------------------------------------------------------------------
# Get-HVQDNextSequence
# Returns the next zero-padded sequence number for a VM name series.
# Queries Get-VM, filters for names matching {Prefix}-{OsCode}-{JoinType}-*,
# extracts the numeric suffix, finds the highest, and returns highest + 1.
# Parameters:
#   Prefix   — from config (e.g. 'HVQD')
#   OsCode   — from profile (e.g. 'W11')
#   JoinType — the selected join type abbreviation (e.g. 'EJ')
# Returns a 2-digit zero-padded string, e.g. '01', '02', '03'
# ---------------------------------------------------------------------------
function Get-HVQDNextSequence {
    param(
        [string]$Prefix,
        [string]$OsCode,
        [string]$JoinType
    )

    $namePrefix = "$Prefix-$OsCode-$JoinType-"

    # Check registered Hyper-V VMs for this name pattern
    $vmSeqs = @(Get-VM -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "$namePrefix*" } |
                ForEach-Object {
                    $suffix = $_.Name.Substring($namePrefix.Length)
                    if ($suffix -match '^\d+$') { [int]$suffix } else { 0 }
                })

    # Also scan the VM root folder on disk so that folders left behind by
    # deleted or failed VMs are not reused, causing 'file already exists' errors.
    $folderSeqs = @()
    $cfg = Get-HVQDConfig -ErrorAction SilentlyContinue
    if ($null -ne $cfg -and -not [string]::IsNullOrEmpty($cfg.VMFolder) -and (Test-Path $cfg.VMFolder)) {
        $folderSeqs = @(Get-ChildItem -Path $cfg.VMFolder -Directory |
            Where-Object { $_.Name -like "$namePrefix*" } |
            ForEach-Object {
                $suffix = $_.Name.Substring($namePrefix.Length)
                if ($suffix -match '^\d+$') { [int]$suffix } else { 0 }
            })
    }

    $allSeqs = @($vmSeqs) + @($folderSeqs) | Where-Object { $_ -gt 0 }

    if ($allSeqs.Count -eq 0) { return '01' }

    $maxSeq = ($allSeqs | Measure-Object -Maximum).Maximum
    $next   = $maxSeq + 1
    return $next.ToString().PadLeft(2, '0')
}

# ---------------------------------------------------------------------------
# New-HVQDVirtualMachine
# Creates a complete Hyper-V VM from config + profile data.
# Steps performed:
#   1. Determine VM name and VHDX path
#   2. Create VHDX subfolder
#   3. Create dynamic VHDX (127 GB)
#   4. Create VM with specified generation
#   5. Set memory (dynamic, startup/min/max all from profile × 1MB)
#   6. Set CPU count (from profile)
#   7. Set generation-specific firmware (SecureBoot, TPM for Gen2)
#   8. Attach DVD drive with ISO
#   9. Connect to network switch
#  10. Configure boot order (Gen2: DVD first)
# Parameters:
#   Config   — loaded config hashtable
#   Profile  — loaded profile hashtable
#   JoinType — selected join type abbreviation
#   IsoPath  — full path to the selected ISO file
#   VMName   — the fully-resolved VM name (passed in after optional rename)
# Returns the name of the created VM.
# ---------------------------------------------------------------------------
function New-HVQDVirtualMachine {
    param(
        [hashtable]$Config,
        [hashtable]$Profile,
        [string]   $JoinType,
        [string]   $IsoPath,
        [string]   $VMName
    )

    # -----------------------------------------------------------------------
    # Step 1 -- Resolve paths
    # -----------------------------------------------------------------------
    # Each VM gets its own subfolder under VMFolder so files don't pile up
    $vmFolder  = Join-Path $Config.VMFolder $VMName
    $vhdxPath  = Join-Path $vmFolder "$VMName.vhdx"

    # -----------------------------------------------------------------------
    # Step 2 — Create VHDX subfolder if it doesn't already exist
    # -----------------------------------------------------------------------
    if (-not (Test-Path $vmFolder)) {
        New-Item -ItemType Directory -Path $vmFolder -Force | Out-Null
    }

    # -----------------------------------------------------------------------
    # Step 3 — Create dynamic VHDX (127 GB is the Hyper-V default)
    # Dynamic means it only uses real disk space as data is written.
    # -----------------------------------------------------------------------
    New-VHD -Path $vhdxPath -SizeBytes (127GB) -Dynamic | Out-Null

    # -----------------------------------------------------------------------
    # Step 4 — Create the VM shell (no DVD or NIC yet — added separately below)
    # MemoryStartupBytes must be provided at creation; memory range set afterwards.
    # -----------------------------------------------------------------------
    $startupBytes = $Profile.MemoryStartupMB * 1MB   # Convert MB → bytes

    $newVMParams = @{
        Name               = $VMName
        Generation         = $Profile.Generation
        MemoryStartupBytes = $startupBytes
        Path               = $vmFolder
        VHDPath            = $vhdxPath
        SwitchName         = $Config.DefaultSwitch
    }
    New-VM @newVMParams | Out-Null

    # -----------------------------------------------------------------------
    # Step 5 — Configure dynamic memory range
    # All three values come from the profile in MB and must be bytes for Set-VMMemory.
    # -----------------------------------------------------------------------
    Set-VMMemory -VMName $VMName `
        -DynamicMemoryEnabled $true `
        -MinimumBytes  ($Profile.MemoryMinimumMB  * 1MB) `
        -StartupBytes  ($Profile.MemoryStartupMB  * 1MB) `
        -MaximumBytes  ($Profile.MemoryMaximumMB  * 1MB)

    # -----------------------------------------------------------------------
    # Step 6 — Set CPU count from profile
    # -----------------------------------------------------------------------
    Set-VMProcessor -VMName $VMName -Count $Profile.ProcessorCount

    # -----------------------------------------------------------------------
    # Step 7 — Generation-specific firmware settings
    # Gen1 uses BIOS — no SecureBoot or TPM capability, skip firmware calls.
    # Gen2 uses UEFI — apply SecureBoot and TPM settings from profile.
    # -----------------------------------------------------------------------
    if ($Profile.Generation -eq 2) {
        Set-VMFirmware -VMName $VMName -EnableSecureBoot $(if ($Profile.SecureBoot) { 'On' } else { 'Off' })

        if ($Profile.TPM -eq $true) {
            # Enable the TPM only if the host has a vTPM key protector available
            $vm = Get-VM -Name $VMName
            Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
            Enable-VMTPM -VMName $VMName
        }
    }

    # -----------------------------------------------------------------------
    # Step 8 — Attach ISO as DVD drive
    # DVD drive is added after creation to allow setting the Path directly.
    # -----------------------------------------------------------------------
    Add-VMDvdDrive -VMName $VMName -Path $IsoPath

    # -----------------------------------------------------------------------
    # Step 9 — Set boot order for Gen2 VMs so they boot from DVD first
    # Gen1 VMs use BIOS boot order which defaults to DVD automatically.
    # -----------------------------------------------------------------------
    if ($Profile.Generation -eq 2) {
        $dvdDrive  = Get-VMDvdDrive  -VMName $VMName
        $hardDrive = Get-VMHardDiskDrive -VMName $VMName
        $netAdapter= Get-VMNetworkAdapter -VMName $VMName

        Set-VMFirmware -VMName $VMName -BootOrder $dvdDrive, $hardDrive, $netAdapter
    }

    # -----------------------------------------------------------------------
    # Step 10 — Auto-start if configured
    # AutoStartVM is a config-level setting, not per-profile.
    # -----------------------------------------------------------------------
    if ($Config.AutoStartVM -eq $true) {
        Start-VM -Name $VMName
    }

    return $VMName
}
