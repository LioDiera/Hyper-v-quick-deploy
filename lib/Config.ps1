# =============================================================================
# Config.ps1 — Configuration load, save, and profile discovery
# Handles all I/O for the per-user config file stored in AppData and the
# per-repo profile .psd1 files stored in the profiles/ folder.
# Config is stored outside the repo so user settings survive clones/updates.
# =============================================================================

# Full path to the user's config file.
# Lives in AppData so it persists across repo clones and is never committed.
$script:ConfigPath = Join-Path $env:APPDATA 'HyperVQuickDeploy\config.psd1'

# ---------------------------------------------------------------------------
# Test-HVQDConfigExists
# Returns $true if the user config file already exists.
# Used by the orchestrator to decide whether to run the first-run wizard.
# ---------------------------------------------------------------------------
function Test-HVQDConfigExists {
    return Test-Path $script:ConfigPath
}

# ---------------------------------------------------------------------------
# Get-HVQDConfig
# Loads the user config from AppData and returns it as a hashtable.
# Caller should call Test-HVQDConfigExists first.
# ---------------------------------------------------------------------------
function Get-HVQDConfig {
    # Import-PowerShellDataFile is the safe way to parse .psd1 — it doesn't
    # execute arbitrary code the way dot-sourcing a script would.
    return Import-PowerShellDataFile -Path $script:ConfigPath
}

# ---------------------------------------------------------------------------
# Save-HVQDConfig
# Writes a config hashtable to disk in .psd1 format.
# Creates the parent directory if it doesn't yet exist (first run).
# Parameters:
#   Config — hashtable containing all config keys
# ---------------------------------------------------------------------------
function Save-HVQDConfig {
    param(
        [hashtable]$Config
    )

    $dir = Split-Path $script:ConfigPath -Parent
    if (-not (Test-Path $dir)) {
        # First run — AppData folder doesn't exist yet
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Serialise to .psd1 manually because PowerShell has no built-in
    # Export-PowerShellDataFile cmdlet in 5.1.
    $lines = @('@{')

    foreach ($key in $Config.Keys) {
        $value = $Config[$key]

        # Emit the correct .psd1 literal depending on value type
        switch ($value) {
            { $_ -is [bool] }   { $lines += "    $key = `$$($value.ToString().ToLower())" }
            { $_ -is [int] }    { $lines += "    $key = $value" }
            default             { $lines += "    $key = '$($value -replace "'", "''")'" }
        }
    }

    $lines += '}'
    $lines | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Get-HVQDDefaultConfig
# Returns a hashtable with sensible defaults shown in the first-run wizard.
# Callers display these values and let the user override them.
# ---------------------------------------------------------------------------
function Get-HVQDDefaultConfig {
    return @{
        IsoFolder      = 'C:\ISOs'
        VMFolder       = 'C:\Hyper-V\VMs'
        Prefix         = 'HVQD'
        DefaultSwitch  = 'Default Switch'
        DefaultProfile = 'windows11.psd1'
        AutoStartVM    = $true
        Locale         = 'en-US'   # Windows locale for unattended answer file (language, keyboard, region)
    }
}

# ---------------------------------------------------------------------------
# Get-HVQDProductKeys
# Loads optional per-user product keys from AppData.  Returns a hashtable
# keyed by WimImageName (e.g. 'Windows 11 Enterprise') whose values are the
# corresponding product key strings.  Returns an empty hashtable when the
# file does not exist so callers fall back to the public GVLK in the profile.
#
# File location: %APPDATA%\HyperVQuickDeploy\keys.psd1
# Format example:
#   @{
#       'Windows 11 Enterprise'                          = 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
#       'Windows 11 Pro'                                 = 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
#       'Windows Server 2025 Standard (Desktop Experience)' = 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
#   }
# The key name must match the WimImageName value in the profile exactly.
# Any entry left blank or omitted falls back to the GVLK for that edition.
# ---------------------------------------------------------------------------
$script:KeysPath = Join-Path $env:APPDATA 'HyperVQuickDeploy\keys.psd1'

function Get-HVQDProductKeys {
    if (Test-Path $script:KeysPath) {
        return Import-PowerShellDataFile -Path $script:KeysPath
    }
    return @{}
}

# ---------------------------------------------------------------------------
# Edit-HVQDProductKeys
# Creates a ready-to-edit keys.psd1 template in AppData (if it does not
# already exist) then opens it in Notepad.  All WimImageName entries are
# pre-populated with empty strings.  Fill in the keys you have; leave the
# rest empty to fall back to the public GVLK for that edition.
# ---------------------------------------------------------------------------
function Edit-HVQDProductKeys {
    $dir = Split-Path $script:KeysPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path $script:KeysPath)) {
        $template = @'
# =============================================================================
# HyperVQuickDeploy -- Product Keys
# Fill in the product keys provided by your organisation.
# Keys are matched by the exact WimImageName used in each profile.
# Leave a value as '' to fall back to the public GVLK for that edition.
# This file is stored in AppData and is never committed to the repo.
# =============================================================================
@{
    # --- Windows 10 ---
    'Windows 10 Enterprise'                                        = ''
    'Windows 10 Pro'                                               = ''
    'Windows 10 Education'                                         = ''

    # --- Windows 11 ---
    'Windows 11 Enterprise'                                        = ''
    'Windows 11 Pro'                                               = ''
    'Windows 11 Education'                                         = ''

    # --- Windows Server 2012 R2 ---
    'Windows Server 2012 R2 Standard (Server with a GUI)'          = ''
    'Windows Server 2012 R2 Standard (Server Core Installation)'   = ''
    'Windows Server 2012 R2 Datacenter (Server with a GUI)'        = ''
    'Windows Server 2012 R2 Datacenter (Server Core Installation)' = ''

    # --- Windows Server 2016 ---
    'Windows Server 2016 Standard (Desktop Experience)'            = ''
    'Windows Server 2016 Standard'                                 = ''
    'Windows Server 2016 Datacenter (Desktop Experience)'          = ''
    'Windows Server 2016 Datacenter'                               = ''

    # --- Windows Server 2019 ---
    'Windows Server 2019 Standard (Desktop Experience)'            = ''
    'Windows Server 2019 Standard'                                 = ''
    'Windows Server 2019 Datacenter (Desktop Experience)'          = ''
    'Windows Server 2019 Datacenter'                               = ''

    # --- Windows Server 2022 ---
    'Windows Server 2022 Standard (Desktop Experience)'            = ''
    'Windows Server 2022 Standard'                                 = ''
    'Windows Server 2022 Datacenter (Desktop Experience)'          = ''
    'Windows Server 2022 Datacenter'                               = ''

    # --- Windows Server 2025 ---
    'Windows Server 2025 Standard (Desktop Experience)'            = ''
    'Windows Server 2025 Standard'                                 = ''
    'Windows Server 2025 Datacenter (Desktop Experience)'          = ''
    'Windows Server 2025 Datacenter'                               = ''
}
'@
        # Write UTF-8 without BOM so Import-PowerShellDataFile reads it cleanly
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($script:KeysPath, $template, $utf8NoBom)
        Write-Host "Created: $script:KeysPath"
    } else {
        Write-Host "Opening existing file: $script:KeysPath"
    }

    Start-Process notepad.exe $script:KeysPath
}

# ---------------------------------------------------------------------------
# Get-HVQDProfiles
# Discovers all *.psd1 files in the profiles/ folder and returns them as an
# ordered array of hashtables (each with a 'File' key added for reference).
# Parameters:
#   RootPath — absolute path to the repo root (passed in from deploy.ps1).
#              Never derived from $PSScriptRoot here because this file lives
#              in lib/, not the repo root, so $PSScriptRoot would be wrong.
# ---------------------------------------------------------------------------
function Get-HVQDProfiles {
    param(
        [string]$RootPath
    )

    $profilesDir = Join-Path $RootPath 'profiles'

    if (-not (Test-Path $profilesDir)) {
        # Guard against a broken install where profiles/ is missing
        return @()
    }

    $results = @()
    $files   = Get-ChildItem -Path $profilesDir -Filter '*.psd1' | Sort-Object Name

    foreach ($file in $files) {
        $data = Import-PowerShellDataFile -Path $file.FullName
        # Attach the filename so the orchestrator can use it as DefaultProfile value
        $data['File'] = $file.Name
        $results += $data
    }

    return $results
}
