# =============================================================================
# HyperVQuickDeploy.psm1 -- Main orchestrator
# Dot-sources all lib files, then runs the end-to-end VM deployment flow.
# The single exported function is Start-HVQuickDeploy, called by deploy.ps1.
#
# Screen flow:
#   First-run wizard -> Pre-flight checks -> ISO picker -> Profile picker
#   -> Join-type picker (skipped if only one option) -> Disk-space check
#   -> Confirm + password + optional rename -> Progress -> Success
# =============================================================================

# Import all lib files.  $PSScriptRoot is valid here because this .psm1 is
# in the repo root -- the same folder that deploy.ps1's $rootPath resolves to.
. "$PSScriptRoot\lib\UI.ps1"
. "$PSScriptRoot\lib\Config.ps1"
. "$PSScriptRoot\lib\Validation.ps1"
. "$PSScriptRoot\lib\HyperV.ps1"
. "$PSScriptRoot\lib\Unattend.ps1"

# ---------------------------------------------------------------------------
# Invoke-HVQDFirstRunWizard
# Interactive wizard shown only once, on first run.
# Collects the four required paths/values and writes config.psd1 to AppData.
# Parameters:
#   RootPath — repo root, used to suggest a sane DefaultProfile
# ---------------------------------------------------------------------------
function Invoke-HVQDFirstRunWizard {
    param([string]$RootPath)

    Clear-Screen
    Write-Header -Title 'FIRST-RUN SETUP'

    Write-Colour '  Welcome!  This wizard runs once to create your config.' -Colour White
    Write-Colour '  Settings are saved to $env:APPDATA\HyperVQuickDeploy\config.psd1' -Colour Gray
    Write-Host ''
    Write-Colour '  Press Enter to accept the default shown in [ brackets ].' -Colour Gray
    Write-Host ''

    $defaults = Get-HVQDDefaultConfig

    # Collect each value; Read-TextInput shows the default and returns it if
    # the user just presses Enter without typing anything.
    $isoFolder = Read-TextInput -Prompt "ISO folder path  (where your .iso files live)" `
                                -Default $defaults.IsoFolder

    $vhdxFolder = Read-TextInput -Prompt "VM folder  (root path where all VM files are stored)" `
                                 -Default $defaults.VMFolder

    $prefix = Read-TextInput -Prompt "VM name prefix  (e.g. HVQD  →  HVQD-W11-EJ-01)" `
                              -Default $defaults.Prefix

    $switch = Read-TextInput -Prompt "Default virtual switch name" `
                              -Default $defaults.DefaultSwitch

    $locale = Read-TextInput -Prompt "Locale  (used in unattended answer file, e.g. en-US)" `
                              -Default $defaults.Locale

    # AutoStartVM: ask for Y/N
    Write-Host ''
    Write-Colour '  Auto-start VM after creation? [Y/n]: ' -Colour White -NoNewline
    $autoInput  = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $autoStart  = ($autoInput.Character -ne 'n' -and $autoInput.Character -ne 'N')
    Write-Host ''

    $config = @{
        IsoFolder      = $isoFolder
        VMFolder       = $vhdxFolder
        Prefix         = $prefix
        DefaultSwitch  = $switch
        DefaultProfile = $defaults.DefaultProfile
        AutoStartVM    = $autoStart
        Locale         = $locale
    }

    Save-HVQDConfig -Config $config

    Write-Host ''
    Write-Colour '  Config saved.  Press any key to continue.' -Colour Green
    $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | Out-Null

    return $config
}

# ---------------------------------------------------------------------------
# Start-HVQuickDeploy
# Entry point called by deploy.ps1.
# Runs the full screen flow from pre-flight through success.
# Parameters:
#   RootPath — absolute path to the repo root (from deploy.ps1's $PSScriptRoot)
# ---------------------------------------------------------------------------
function Start-HVQuickDeploy {
    param([string]$RootPath)

    # ------------------------------------------------------------------
    # Phase 1 — Load or create config
    # ------------------------------------------------------------------
    if (-not (Test-HVQDConfigExists)) {
        $config = Invoke-HVQDFirstRunWizard -RootPath $RootPath
    } else {
        $config = Get-HVQDConfig
    }
    $productKeys = Get-HVQDProductKeys

    # ------------------------------------------------------------------
    # Phase 2 — Pre-flight checks
    # Blocking failures are shown as error notifications; warn-only checks
    # (network switch) are shown separately and do not stop the flow.
    # ------------------------------------------------------------------
    $failures = Invoke-HVQDPreflightChecks -Config $config

    if ($failures.Count -gt 0) {
        foreach ($f in $failures) {
            Write-Notification -Title $f.Check -Message $f.Message -Hint $f.Hint -Colour Red
        }
        return   # Stop here — cannot safely proceed
    }

    # Non-blocking check: warn if the configured switch doesn't exist
    if (-not (Test-HVQDNetworkSwitch -SwitchName $config.DefaultSwitch)) {
        Write-Notification `
            -Title   "Virtual Switch Not Found" `
            -Message "The switch '$($config.DefaultSwitch)' does not exist in Hyper-V." `
            -Hint    "The VM will still be created but may have no network connectivity." `
            -Colour  Yellow
        # Flow continues after the user acknowledges
    }

    # ------------------------------------------------------------------
    # Phase 3 — Screen 1: ISO picker
    # ------------------------------------------------------------------
    $isoResult = Test-HVQDIsoFolder -IsoFolder $config.IsoFolder
    # IsoFolder was already validated in pre-flight, but re-check to get the file list
    $isoFiles = $isoResult.IsoFiles | Sort-Object Name

    $isoNames = $isoFiles | ForEach-Object { $_.Name }
    $selectedIsoName = Select-FromList -Items $isoNames -Title 'SELECT ISO'

    if ($null -eq $selectedIsoName) {
        # User pressed Escape — bail out gracefully
        Clear-Screen
        Write-Colour '  Cancelled.' -Colour Gray
        return
    }

    $selectedIso = $isoFiles | Where-Object { $_.Name -eq $selectedIsoName } | Select-Object -First 1
    $isoPath = $selectedIso.FullName

    # ------------------------------------------------------------------
    # Phase 4 — Screen 2: Profile picker
    # ------------------------------------------------------------------
    $profiles = Get-HVQDProfiles -RootPath $RootPath

    if ($profiles.Count -eq 0) {
        Write-Notification `
            -Title   "No Profiles Found" `
            -Message "No .psd1 profiles were found in the profiles/ folder." `
            -Hint    "Ensure the profiles/ directory exists and contains .psd1 files." `
            -Colour  Red
        return
    }

    # Pre-highlight the DefaultProfile from config
    $defaultProfileIndex = 0
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        if ($profiles[$i].File -eq $config.DefaultProfile) {
            $defaultProfileIndex = $i
            break
        }
    }

    $profileNames     = $profiles | ForEach-Object { $_.Name }
    $selectedProfName = Select-FromList -Items $profileNames -DefaultIndex $defaultProfileIndex -Title 'SELECT OS PROFILE' -SubInfo "ISO: $selectedIsoName"

    if ($null -eq $selectedProfName) {
        Clear-Screen
        Write-Colour '  Cancelled.' -Colour Gray
        return
    }

    $selectedProfile = $profiles | Where-Object { $_.Name -eq $selectedProfName } | Select-Object -First 1

    # ------------------------------------------------------------------
    # Phase 4b -- Screen 2b: Edition picker
    # Shown only when the profile defines two or more editions.
    # ------------------------------------------------------------------
    $selectedEdition = $null
    $editionList     = @()
    if ($null -ne $selectedProfile.Editions) { $editionList = @($selectedProfile.Editions) }

    if ($editionList.Count -gt 1) {
        $editionNames        = $editionList | ForEach-Object { $_.Name }
        $selectedEditionName = Select-FromList -Items   $editionNames `
                                               -Title   'SELECT EDITION' `
                                               -SubInfo "Profile: $($selectedProfile.Name)"
        if ($null -eq $selectedEditionName) {
            Clear-Screen
            Write-Colour '  Cancelled.' -Colour Gray
            return
        }
        $selectedEdition = $editionList |
                           Where-Object { $_.Name -eq $selectedEditionName } |
                           Select-Object -First 1
    } elseif ($editionList.Count -eq 1) {
        $selectedEdition = $editionList[0]
    }

    # Apply edition overrides so the correct key/image flow through to
    # the confirm screen label, the XML generator, and any future code.
    if ($null -ne $selectedEdition) {
        $selectedProfile['KmsKey']       = $selectedEdition.KmsKey
        $selectedProfile['WimImageName'] = $selectedEdition.WimImageName
    }

    # ------------------------------------------------------------------
    # Phase 5 — Screen 3: Join-type picker (skipped when only one option)
    # ------------------------------------------------------------------
    $joinTypeMap = @{
        EJ  = 'Entra Joined'
        HEJ = 'Hybrid Entra Joined'
        ER  = 'Entra Registered'
        DJ  = 'Domain Joined'
        WG  = 'Workgroup'
    }

    $joinTypes = $selectedProfile.JoinTypes

    if ($joinTypes.Count -eq 1) {
        # Auto-select the only option — no screen shown
        $selectedJoinType = $joinTypes[0]
    } else {
        # Build display labels that include both abbreviation and full name
        $joinLabels = $joinTypes | ForEach-Object {
            $abbr = $_
            $full = $joinTypeMap[$abbr]
            if ($full) { "$abbr - $full" } else { $abbr }
        }

        $selectedLabel = Select-FromList -Items $joinLabels -Title 'SELECT JOIN TYPE' -SubInfo "Profile: $($selectedProfile.Name)"

        if ($null -eq $selectedLabel) {
            Clear-Screen
            Write-Colour '  Cancelled.' -Colour Gray
            return
        }

        # Extract the abbreviation before ' — '
        $selectedJoinType = $selectedLabel.Split(' ')[0]
    }

    # ------------------------------------------------------------------
    # Phase 6 -- Post-profile disk space check
    # Now we know VMFolder, so we can check available space.
    # ------------------------------------------------------------------
    $diskResult = Test-HVQDDiskSpace -VMFolder $config.VMFolder

    if (-not $diskResult.OK) {
        Write-Notification `
            -Title   "Insufficient Disk Space" `
            -Message "Need at least 127 GB free on $($config.VMFolder). Found: $($diskResult.FreeGB) GB." `
            -Hint    "Free up disk space or change the VHDX folder to another drive." `
            -Colour  Red
        return
    }

    # ------------------------------------------------------------------
    # Phase 7 — Resolve VM name and sequence number
    # ------------------------------------------------------------------
    $sequence = Get-HVQDNextSequence -Prefix $config.Prefix `
                                     -OsCode $selectedProfile.OsCode `
                                     -JoinType $selectedJoinType

    $vmName = "$($config.Prefix)-$($selectedProfile.OsCode)-$selectedJoinType-$sequence"

    # ------------------------------------------------------------------
    # Phase 8 — Screen 4: Confirm settings
    # User can rename ([N]) or proceed to create ([C]).
    # ------------------------------------------------------------------
    $confirmed     = $false
    $adminPassword  = ''

    # Mutable VM spec -- initialised from the profile, editable on the confirm screen
    $vmMemStartupMB = [int]$selectedProfile.MemoryStartupMB
    $vmMemMinMB     = [int]$selectedProfile.MemoryMinimumMB
    $vmMemMaxMB     = [int]$selectedProfile.MemoryMaximumMB
    $vmCpuCount     = [int]$selectedProfile.ProcessorCount
    $vmDiskGB       = 127
    $vmSwitch       = $config.DefaultSwitch

    while (-not $confirmed) {
        Clear-Screen
        Write-Header -Title 'CONFIRM SETTINGS' -SubInfo "ISO: $selectedIsoName"

        Write-SummaryRow -Key 'VM Name'    -Value $vmName       -Colour White
        Write-SummaryRow -Key 'Profile'    -Value $selectedProfile.Name -Colour White
        if ($null -ne $selectedEdition) {
            Write-SummaryRow -Key 'Edition' -Value $selectedEdition.Name -Colour White
        }
        Write-SummaryRow -Key 'Join Type'  -Value "$selectedJoinType - $($joinTypeMap[$selectedJoinType])" -Colour White
        Write-SummaryRow -Key 'Generation' -Value "Gen $($selectedProfile.Generation)" -Colour White
        Write-SummaryRow -Key 'Memory'     -Value "$vmMemStartupMB MB startup  ($vmMemMinMB-$vmMemMaxMB MB)" -Colour Cyan
        Write-SummaryRow -Key 'CPUs'       -Value "$vmCpuCount vCPU(s)" -Colour Cyan
        Write-SummaryRow -Key 'Disk'       -Value "$vmDiskGB GB dynamic VHDX" -Colour Cyan
        Write-SummaryRow -Key 'Switch'     -Value $vmSwitch -Colour Cyan

        # Only show SecureBoot and TPM rows for Gen2 VMs
        if ($selectedProfile.Generation -eq 2) {
            Write-SummaryRow -Key 'Secure Boot' -Value $(if ($selectedProfile.SecureBoot) { 'Enabled' } else { 'Disabled' }) -Colour White
            Write-SummaryRow -Key 'TPM'         -Value $(if ($selectedProfile.TPM) { 'Enabled' } else { 'Disabled' }) -Colour White
        }

        Write-SummaryRow -Key 'Auto-start' -Value $(if ($config.AutoStartVM) { 'Yes' } else { 'No' }) -Colour White

        # Ubuntu cannot use autounattend.xml -- show a warning instead of the password row
        $isUbuntu = ($selectedProfile.OsCode -eq 'UBU')
        if ($isUbuntu) {
            Write-SummaryRow -Key 'Unattended' -Value 'Not supported -- manual setup required' -Colour Yellow
        } else {
            # Show password status: yellow (required) until set, green once set
            $pwStatus = if ($adminPassword) { '(set)' } else { '(required -- press P)' }
            $pwColour = if ($adminPassword) { 'Green' } else { 'Yellow' }
            Write-SummaryRow -Key 'Admin Pass' -Value $pwStatus -Colour $pwColour
        }

        Write-SummaryRow -Key 'VM Path' -Value "$($config.VMFolder)\$vmName\" -Colour Gray

        if ($isUbuntu) {
            Write-ActionBar -Actions '[ M ] Memory  [ V ] vCPUs  [ D ] Disk  [ S ] Switch' `
                            -Actions2 '[ C ] Create  [ N ] Rename  [ Esc ] Cancel'
        } else {
            Write-ActionBar -Actions '[ M ] Memory  [ V ] vCPUs  [ D ] Disk  [ S ] Switch  [ P ] Password' `
                            -Actions2 '[ C ] Create  [ N ] Rename  [ Esc ] Cancel'
        }

        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

        switch ($key.Character.ToString().ToLower()) {
            'c' {
                # Block create for Windows profiles until an admin password is set.
                # Without it the autounattend.xml would contain a blank Administrator password.
                if (-not $isUbuntu -and -not $adminPassword) {
                    # Loop redraws showing the '(required -- press P)' hint
                } else {
                    $confirmed = $true
                }
            }
            'n' {
                # Inline rename -- prompt replaces the current name
                $newName = Read-TextInput -Prompt 'New VM name:' -Default $vmName
                if (-not [string]::IsNullOrWhiteSpace($newName)) {
                    $vmName = $newName.Trim()
                }
            }
            'm' {
                $raw = Read-TextInput -Prompt 'Startup memory (MB):' -Default "$vmMemStartupMB"
                $parsed = 0
                if ([int]::TryParse($raw.Trim(), [ref]$parsed) -and $parsed -ge 512) {
                    $vmMemStartupMB = $parsed
                    $vmMemMaxMB     = [Math]::Max($vmMemMaxMB, $vmMemStartupMB)
                    $vmMemMinMB     = [Math]::Min($vmMemMinMB, $vmMemStartupMB)
                }
            }
            'v' {
                $raw = Read-TextInput -Prompt 'vCPU count:' -Default "$vmCpuCount"
                $parsed = 0
                if ([int]::TryParse($raw.Trim(), [ref]$parsed) -and $parsed -ge 1) {
                    $vmCpuCount = $parsed
                }
            }
            'd' {
                $raw = Read-TextInput -Prompt 'Disk size (GB):' -Default "$vmDiskGB"
                $parsed = 0
                if ([int]::TryParse($raw.Trim(), [ref]$parsed) -and $parsed -ge 20) {
                    $vmDiskGB = $parsed
                }
            }
            's' {
                $availableSwitches = @(Get-VMSwitch | Select-Object -ExpandProperty Name | Sort-Object)
                if ($availableSwitches.Count -gt 0) {
                    $picked = Select-FromList -Items $availableSwitches -Title 'SELECT NETWORK SWITCH' -SubInfo "Current: $vmSwitch"
                    if ($null -ne $picked) { $vmSwitch = $picked }
                }
            }
            'p' {
                if (-not $isUbuntu) {
                    Write-Host ''
                    Write-Colour '  Admin password:   ' -Colour White -NoNewline
                    $securePwd1 = Read-Host -AsSecureString
                    Write-Colour '  Confirm password: ' -Colour White -NoNewline
                    $securePwd2 = Read-Host -AsSecureString

                    if ($securePwd1.Length -eq 0) {
                        # Nothing entered -- ignore
                    } else {
                        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd1)
                        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd2)
                        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
                        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
                        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)

                        if ($plain1 -eq $plain2) {
                            $adminPassword = $plain1
                        } else {
                            Write-Colour '  Passwords do not match -- try again.' -Colour Red
                            Start-Sleep -Seconds 2
                        }
                        $plain1 = $null
                        $plain2 = $null
                    }
                }
            }
        }

        if ($key.VirtualKeyCode -eq 27) {
            # Escape pressed -- cancel
            Clear-Screen
            Write-Colour '  Cancelled.' -Colour Gray
            return
        }
    }

    # Build the step list based on profile type and AutoStartVM config.
    # Ubuntu cannot use autounattend.xml so answer-file steps are skipped for it.
    $isUbuntu = ($selectedProfile.OsCode -eq 'UBU')

    $steps = @(
        'Creating VM folder',
        "Creating dynamic VHDX ($vmDiskGB GB)",
        'Creating VM',
        'Configuring memory',
        'Configuring CPU',
        'Configuring firmware',
        'Attaching ISO'
    )

    if (-not $isUbuntu) {
        $steps += 'Generating answer file'
        $steps += 'Creating answer media'
    }

    # Boot order is always set after ALL DVD drives are attached so the
    # OS ISO reference is stable (answer ISO is a second DVD on Windows).
    $steps += 'Setting boot order'

    if ($config.AutoStartVM) {
        $steps += 'Starting VM'
    }

    # Indices depend on whether answer steps were included
    $bootOrderIndex = if ($isUbuntu) { 7 } else { 9 }
    $startVmIndex   = if ($isUbuntu) { 8 } else { 10 }

    try {
        # ---- Step 0: VM folder ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 0
        $vmFolder = Join-Path $config.VMFolder $vmName
        if (-not (Test-Path $vmFolder)) {
            New-Item -ItemType Directory -Path $vmFolder -Force | Out-Null
        }

        # ---- Step 1: Create VHDX ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 1
        $vhdxPath = Join-Path $vmFolder "$vmName.vhdx"
        New-VHD -Path $vhdxPath -SizeBytes ([int64]$vmDiskGB * 1GB) -Dynamic | Out-Null

        # ---- Step 2: Create VM ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 2
        New-VM -Name $vmName `
               -Generation $selectedProfile.Generation `
               -MemoryStartupBytes ($vmMemStartupMB * 1MB) `
               -Path $vmFolder `
               -VHDPath $vhdxPath `
               -SwitchName $vmSwitch | Out-Null

        # ---- Step 3: Memory ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 3
        Set-VMMemory -VMName $vmName `
            -DynamicMemoryEnabled $true `
            -MinimumBytes ($vmMemMinMB * 1MB) `
            -StartupBytes ($vmMemStartupMB * 1MB) `
            -MaximumBytes ($vmMemMaxMB * 1MB)

        # ---- Step 4: CPU ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 4
        Set-VMProcessor -VMName $vmName -Count $vmCpuCount

        # ---- Step 5: Firmware (Gen2 only) ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 5
        if ($selectedProfile.Generation -eq 2) {
            Set-VMFirmware -VMName $vmName -EnableSecureBoot $(if ($selectedProfile.SecureBoot) { 'On' } else { 'Off' })

            if ($selectedProfile.TPM -eq $true) {
                $vm = Get-VM -Name $vmName
                Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
                Enable-VMTPM -VMName $vmName
            }
        }

        # ---- Step 6: Attach ISO ----
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 6
        Add-VMDvdDrive -VMName $vmName -Path $isoPath

        # ---- Steps 7+8: Answer file + media (Windows profiles only) ----
        # Done BEFORE boot order so both DVD drives exist when we set the order.
        if (-not $isUbuntu) {
            Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 7
            $xmlContent = New-HVQDAnswerXml -Profile      $selectedProfile `
                                            -Config       $config `
                                            -VMName       $vmName `
                                            -AdminPassword $adminPassword `
                                            -ProductKeys  $productKeys

            Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex 8
            New-HVQDAnswerMedia -VMName    $vmName `
                                -VMFolder  $config.VMFolder `
                                -XmlContent $xmlContent
        }

        # ---- Boot order (Gen2 only) — set after ALL DVD drives are attached ----
        # Filter by $isoPath so we always boot from the OS install disc,
        # not the answer-file ISO that was added as a second DVD drive.
        Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex $bootOrderIndex
        if ($selectedProfile.Generation -eq 2) {
            $osDvd      = Get-VMDvdDrive        -VMName $vmName | Where-Object { $_.Path -eq $isoPath }
            $hardDrive  = Get-VMHardDiskDrive   -VMName $vmName
            $netAdapter = Get-VMNetworkAdapter  -VMName $vmName
            Set-VMFirmware -VMName $vmName -BootOrder $osDvd, $hardDrive, $netAdapter
        }

        # ---- Starting VM (optional) ----
        if ($config.AutoStartVM) {
            Write-ProgressScreen -VMName $vmName -Steps $steps -ActiveIndex $startVmIndex
            Start-VM -Name $vmName

            # Dismiss "Press any key to boot from CD or DVD" using a runspace
            # (same-process thread) instead of Start-Job.  Start-Job spawns a new
            # PowerShell process (~2-3 s startup) which misses the boot prompt.
            # A runspace starts in ~100 ms and begins pressing immediately.
            $rsScript = {
                param($n)
                $deadline = [DateTime]::UtcNow.AddSeconds(12)
                while ([DateTime]::UtcNow -lt $deadline) {
                    try {
                        $c = Get-CimInstance -Namespace 'root/virtualization/v2' `
                                             -ClassName  'Msvm_ComputerSystem' `
                                             -Filter     "ElementName='$n'" `
                                             -ErrorAction Stop
                        $k = Get-CimAssociatedInstance -InputObject $c `
                                                       -ResultClassName 'Msvm_Keyboard' `
                                                       -ErrorAction Stop
                        Invoke-CimMethod -InputObject $k `
                                         -MethodName  'TypeKey' `
                                         -Arguments   @{ keyCode = 32 } | Out-Null
                    } catch {}
                    Start-Sleep -Milliseconds 200
                }
            }
            $rs  = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
            $rs.Open()
            $rps = [System.Management.Automation.PowerShell]::Create()
            $rps.Runspace = $rs
            [void]$rps.AddScript($rsScript).AddArgument($vmName)
            [void]$rps.BeginInvoke()
        }

        # ------------------------------------------------------------------
        # Phase 10 — Screen 6: Success summary
        # ------------------------------------------------------------------
        Clear-Screen
        Write-StatusHeader -Message 'VM Created Successfully' -Colour Green
        Write-SummaryRow   -Key 'VM Name'   -Value $vmName        -Colour White
        Write-SummaryRow   -Key 'Profile'   -Value $selectedProfile.Name -Colour White
        if ($null -ne $selectedEdition) {
            Write-SummaryRow -Key 'Edition' -Value $selectedEdition.Name -Colour White
        }
        Write-SummaryRow   -Key 'Join Type' -Value "$selectedJoinType - $($joinTypeMap[$selectedJoinType])" -Colour White
        Write-SummaryRow   -Key 'ISO'       -Value $selectedIsoName -Colour White
        Write-SummaryRow   -Key 'Status'    -Value $(if ($config.AutoStartVM) { 'Running' } else { 'Off' }) -Colour Green

        if (-not $config.AutoStartVM) {
            Write-SummaryRow -Key 'Next' `
                             -Value 'Start VM, then press any key in the console to boot from DVD' `
                             -Colour Yellow
        }

        Write-ActionBar -Actions '[ Any key ] Exit'

        $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') | Out-Null

    } catch {
        # Surface raw exceptions as a clean error notification so the user
        # sees a plain-English message rather than a red stack trace.
        Write-Notification `
            -Title   "VM Creation Failed" `
            -Message $_.Exception.Message `
            -Hint    'Check the Hyper-V event log or re-run as Administrator.' `
            -Colour  Red
    }
}

# Export only the public entry point — all other functions are module-internal
Export-ModuleMember -Function 'Start-HVQuickDeploy', 'Edit-HVQDProductKeys'
