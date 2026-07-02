# =============================================================================
# Validation.ps1 — Pre-flight environment checks
# Verifies that the host is in a state where VM creation can succeed before
# anything is committed.  Returns structured results so the orchestrator can
# present clear, actionable error messages rather than raw exception text.
# =============================================================================

# ---------------------------------------------------------------------------
# Test-HVQDIsAdmin
# Checks whether the current process has elevated (Administrator) privileges.
# Hyper-V cmdlets require elevation — failing early is better than a cryptic
# "access denied" mid-operation.
# Returns $true if elevated, $false otherwise.
# ---------------------------------------------------------------------------
function Test-HVQDIsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------------------
# Test-HVQDHyperVEnabled
# Confirms the Hyper-V management cmdlets are available and the host is
# reachable.  Using Get-VMHost is lighter than querying optional features,
# and works the same way on 5.1 and 7+.
# Returns $true if Hyper-V is available, $false otherwise.
# ---------------------------------------------------------------------------
function Test-HVQDHyperVEnabled {
    try {
        # Get-VMHost throws if the Hyper-V service is absent or unreachable
        $null = Get-VMHost -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Test-HVQDIsoFolder
# Verifies that the configured IsoFolder exists and contains at least one
# .iso file.  Failing here gives a clear "no ISOs found" message instead of
# an empty file-picker screen that would confuse the user.
# Parameters:
#   IsoFolder — path from config
# Returns a hashtable: { OK = $bool; IsoFiles = [FileInfo[]] }
# ---------------------------------------------------------------------------
function Test-HVQDIsoFolder {
    param([string]$IsoFolder)

    if (-not (Test-Path $IsoFolder)) {
        return @{ OK = $false; IsoFiles = @() }
    }

    $isoFiles = @(Get-ChildItem -Path $IsoFolder -Filter '*.iso' -File)
    return @{
        OK       = ($isoFiles.Count -gt 0)
        IsoFiles = $isoFiles
    }
}

# ---------------------------------------------------------------------------
# Test-HVQDNetworkSwitch
# Checks whether the named virtual switch exists in Hyper-V.
# This is non-blocking — a missing switch produces a yellow ⚠ warning, not
# a hard stop, because the user might want to create the switch manually.
# Parameters:
#   SwitchName — value from config's DefaultSwitch key
# Returns $true if found, $false if not.
# ---------------------------------------------------------------------------
function Test-HVQDNetworkSwitch {
    param([string]$SwitchName)

    try {
        $switch = Get-VMSwitch -Name $SwitchName -ErrorAction Stop
        return ($null -ne $switch)
    } catch {
        # Get-VMSwitch throws when the switch doesn't exist — treat as not found
        return $false
    }
}

# ---------------------------------------------------------------------------
# Test-HVQDDiskSpace
# Checks that the drive hosting VMFolder has at least 127 GB of free space.
# This runs after the profile is chosen because we know the VHDX is always
# 127 GB dynamically expanding.  Checked post-profile so we know the target
# folder before evaluating disk space.
# Parameters:
#   VMFolder -- path from config where all VM files are created
# Returns a hashtable: { OK = $bool; FreeGB = [double] }
# ---------------------------------------------------------------------------
function Test-HVQDDiskSpace {
    param([string]$VMFolder)

    # Resolve the drive root from the VMFolder path
    # PSDrive is preferred over WMI -- it works reliably on both PS 5.1 and 7
    $driveLetter = (Split-Path -Qualifier $VMFolder).TrimEnd(':')

    try {
        $drive  = Get-PSDrive -Name $driveLetter -ErrorAction Stop
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        return @{
            OK     = ($freeGB -ge 127)
            FreeGB = $freeGB
        }
    } catch {
        # Can't determine free space — fail safe by blocking the deploy
        return @{ OK = $false; FreeGB = 0 }
    }
}

# ---------------------------------------------------------------------------
# Invoke-HVQDPreflightChecks
# Runs all blocking pre-flight checks and returns an array of failure objects.
# Each failure has: { Check = 'name'; Message = '...'; Hint = '...' }
# An empty array means all checks passed.
# Parameters:
#   Config — the loaded config hashtable
# ---------------------------------------------------------------------------
function Invoke-HVQDPreflightChecks {
    param([hashtable]$Config)

    $failures = @()

    # Check 1 — Must be running as Administrator
    if (-not (Test-HVQDIsAdmin)) {
        $failures += @{
            Check   = 'Administrator'
            Message = 'This module must be run as Administrator.'
            Hint    = 'Right-click PowerShell and choose "Run as administrator", then try again.'
        }
    }

    # Check 2 — Hyper-V must be enabled and accessible
    if (-not (Test-HVQDHyperVEnabled)) {
        $failures += @{
            Check   = 'Hyper-V'
            Message = 'Hyper-V is not enabled or the management service is unavailable.'
            Hint    = 'Enable Hyper-V via: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All'
        }
    }

    # Check 3 — ISO folder must exist and have at least one .iso file
    $isoResult = Test-HVQDIsoFolder -IsoFolder $Config.IsoFolder
    if (-not $isoResult.OK) {
        $msg  = if (Test-Path $Config.IsoFolder) {
            "No .iso files found in: $($Config.IsoFolder)"
        } else {
            "ISO folder does not exist: $($Config.IsoFolder)"
        }
        $failures += @{
            Check   = 'IsoFolder'
            Message = $msg
            Hint    = 'Place at least one .iso file in the configured folder or update the path in first-run config.'
        }
    }

    return $failures
}
