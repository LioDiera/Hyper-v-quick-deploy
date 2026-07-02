# =============================================================================
# Unattend.ps1 -- Answer file generation and answer media creation
# Generates autounattend.xml for fully unattended Windows installation and
# packages it into a small FAT32 VHD that Windows Setup finds automatically
# on boot.  No external tools (ADK, oscdimg, Packer) are required.
# Compatible with PowerShell 5.1 and 7+.
# =============================================================================

# ---------------------------------------------------------------------------
# New-HVQDAnswerXml
# Builds and returns an autounattend.xml string tailored to the given profile
# and deploy-time parameters.
#
# Windows Setup scans every accessible drive for autounattend.xml at the root
# during the windowsPE phase.  The XML produced here covers three passes:
#   windowsPE  -- disk layout, image selection, product key, EULA accept
#   specialize -- computer name, timezone (first real boot after setup)
#   oobeSystem -- bypass all OOBE screens, set Administrator password
#
# Parameters:
#   Profile       -- loaded profile hashtable (must include Generation, KmsKey, WimImageName)
#   Config        -- loaded config hashtable (must include Locale, TimeZone)
#   VMName        -- computer name written into the specialize pass
#   AdminPassword -- plain-text password for the built-in Administrator account;
#                    written into the XML as plain text (acceptable for lab VMs)
# ---------------------------------------------------------------------------
function New-HVQDAnswerXml {
    param(
        [hashtable]$Profile,
        [hashtable]$Config,
        [string]   $VMName,
        [string]   $AdminPassword,
        [hashtable]$ProductKeys = @{}
    )

    # ------------------------------------------------------------------
    # Disk layout differs by generation:
    #   Gen2 (UEFI) requires GPT: EFI partition + MSR + Windows
    #   Gen1 (BIOS) uses MBR: System Reserved (active) + Windows
    # The Windows partition ID is referenced in <InstallTo> below.
    # ------------------------------------------------------------------
    if ($Profile.Generation -eq 2) {
        $windowsPartitionId = 3
        $diskConfig = @'
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order><Type>EFI</Type><Size>100</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order><Type>MSR</Type><Size>16</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order><Type>Primary</Type><Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order><PartitionID>1</PartitionID>
              <Label>EFI</Label><Format>FAT32</Format>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order><PartitionID>3</PartitionID>
              <Label>Windows</Label><Format>NTFS</Format><Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
'@
    } else {
        $windowsPartitionId = 2
        $diskConfig = @'
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order><Type>Primary</Type><Size>500</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order><Type>Primary</Type><Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order><PartitionID>1</PartitionID>
              <Label>System</Label><Format>NTFS</Format><Active>true</Active>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order><PartitionID>2</PartitionID>
              <Label>Windows</Label><Format>NTFS</Format><Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
'@
    }

    # ------------------------------------------------------------------
    # $activationKey — Applied post-install in the specialize pass via
    #   slmgr.vbs /ipk.  Priority: user's key from keys.psd1 (MAK / volume
    #   key) > profile GVLK (for KMS environments).
    # ------------------------------------------------------------------
    $activationKey = ''

    if ($ProductKeys.ContainsKey($Profile.WimImageName) -and
        -not [string]::IsNullOrEmpty($ProductKeys[$Profile.WimImageName])) {
        $activationKey = $ProductKeys[$Profile.WimImageName]
    } elseif (-not [string]::IsNullOrEmpty($Profile.KmsKey)) {
        $activationKey = $Profile.KmsKey
    }

    # <ProductKey> block — behaviour differs by edition type:
    #
    # Client (W10 / W11) — no WimImageIndex:
    #   WinPE resolves the edition-specific EULA from the product key.
    #   Omitting the key or using <Key/> causes "cannot find License Terms".
    #   Use the GVLK so WinPE identifies the correct edition; /IMAGE/NAME
    #   then selects it unambiguously.
    #
    # Server editions with WimImageIndex (WS2016/2019/2022/2025):
    #   Server EULAs are generic and not key-dependent, so an empty <Key/>
    #   is safe.  More importantly, WS2022's older WinPE treats any tier
    #   GVLK (e.g. Datacenter) as covering *both* Core and Desktop
    #   Experience, forcing the edition picker regardless of <ImageInstall>.
    #   Empty <Key/> satisfies the parser, applies no tier filter, and lets
    #   /IMAGE/INDEX select the exact image without user interaction.
    #   The real key ($activationKey) is applied post-install via slmgr.
    $useIndexSelection = ($null -ne $Profile.WimImageIndex -and [int]$Profile.WimImageIndex -gt 0)
    if ($useIndexSelection) {
        $productKeyXml = @'
        <ProductKey>
          <Key/>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
'@
    } else {
        $setupKey = $Profile.KmsKey
        if (-not [string]::IsNullOrEmpty($setupKey)) {
            $productKeyXml = @"
        <ProductKey>
          <Key>$setupKey</Key>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
"@
        } else {
            $productKeyXml = ''
        }
    }

    # ------------------------------------------------------------------
    # Specialize-pass activation command (when a key is available).
    # Runs cscript slmgr.vbs /ipk on first boot to install the key.
    # //B suppresses all dialog boxes so it runs silently.
    # ------------------------------------------------------------------
    $slmgrCommandXml = ''
    if (-not [string]::IsNullOrEmpty($activationKey)) {
        $slmgrCommandXml = @"
    <component name="Microsoft-Windows-Deployment"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>cscript.exe //B %SystemRoot%\System32\slmgr.vbs /ipk $activationKey</Path>
          <WillReboot>Never</WillReboot>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
"@
    }

    # ------------------------------------------------------------------
    # Image selection block.
    # Server editions share one GVLK across Core and Desktop Experience, so
    # /IMAGE/NAME combined with <ProductKey> causes older WinPE (WS2022 and
    # earlier) to show the edition picker despite the name matching exactly.
    # /IMAGE/INDEX is unambiguous and avoids the conflict entirely.
    # Profiles set WimImageIndex on each edition for this reason.
    # Fall back to /IMAGE/NAME for Windows client profiles (W11/W10) where
    # there is a 1:1 GVLK-to-image mapping and the picker is never triggered.
    # ------------------------------------------------------------------
    $imageInstallXml = ''
    if (-not [string]::IsNullOrEmpty($Profile.WimImageName)) {
        $metaKey   = '/IMAGE/NAME'
        $metaValue = $Profile.WimImageName
        if ($null -ne $Profile.WimImageIndex -and [int]$Profile.WimImageIndex -gt 0) {
            $metaKey   = '/IMAGE/INDEX'
            $metaValue = [string][int]$Profile.WimImageIndex
        }
        $imageInstallXml = @"
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>$metaKey</Key>
              <Value>$metaValue</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>$windowsPartitionId</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
"@
    }

    # ------------------------------------------------------------------
    # Full XML document.  processorArchitecture="amd64" and the publicKeyToken
    # are required by Windows Setup and are the same for all modern Windows.
    # ------------------------------------------------------------------
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">

  <!-- windowsPE pass: disk layout, image selection, product key, EULA -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <InputLocale>$($Config.Locale)</InputLocale>
      <SystemLocale>$($Config.Locale)</SystemLocale>
      <UILanguage>$($Config.Locale)</UILanguage>
      <UserLocale>$($Config.Locale)</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
$diskConfig
$imageInstallXml
      <UserData>
        <AcceptEula>true</AcceptEula>
$productKeyXml
      </UserData>
    </component>
  </settings>

  <!-- specialize pass: computer name, timezone, optional org activation key -->
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ComputerName>$VMName</ComputerName>
      <TimeZone>$([System.TimeZoneInfo]::Local.Id)</TimeZone>
    </component>
$slmgrCommandXml  </settings>

  <!-- oobeSystem pass: bypass all OOBE screens and set the Administrator password -->
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup"
               processorArchitecture="amd64"
               publicKeyToken="31bf3856ad364e35"
               language="neutral"
               versionScope="nonSxS"
               xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <NetworkLocation>Work</NetworkLocation>
        <SkipUserOOBE>true</SkipUserOOBE>
        <SkipMachineOOBE>true</SkipMachineOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>$AdminPassword</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Password>
              <Value>$AdminPassword</Value>
              <PlainText>true</PlainText>
            </Password>
            <DisplayName>Lab Admin</DisplayName>
            <Group>Administrators</Group>
            <Name>labadmin</Name>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
    </component>
  </settings>

</unattend>
"@

    return $xml
}

# ---------------------------------------------------------------------------
# New-HVQDAnswerMedia
# Creates a small ISO containing autounattend.xml and attaches it to the VM
# as a second DVD drive.
#
# Windows Setup (WinPE) ONLY auto-scans optical drives and USB for answer
# files -- it does NOT scan fixed SCSI disks, even with the 'UNATTEND' volume
# label.  Attaching the answer file as a DVD drive guarantees discovery.
#
# The ISO is built with the IMAPI2FS COM object (built into Windows).
# No external tools, no diskpart, no VHD mounting required.
#
# Parameters:
#   VMName     -- name of the VM to attach the media to
#   VMFolder   -- root VM folder; ISO is created in {VMFolder}\{VMName}\
#   XmlContent -- the XML string returned by New-HVQDAnswerXml
# Returns the full path to the created ISO.
# ---------------------------------------------------------------------------
function New-HVQDAnswerMedia {
    param(
        [string]$VMName,
        [string]$VMFolder,
        [string]$XmlContent
    )

    $vmSubfolder = Join-Path $VMFolder $VMName
    $isoPath     = Join-Path $vmSubfolder "$VMName-unattend.iso"

    # ---- One-time: compile a C# helper for reading the IMAPI2 COM IStream ----
    # PowerShell's script-level ComTypes.IStream.Read() does not correctly
    # marshal the pcbRead IntPtr out-parameter back to the caller -- the loop
    # either spins forever or reads garbage counts.  Compiled C# handles COM
    # interop correctly, so we compile a tiny static helper the first time and
    # reuse it on subsequent calls within the same session.
    if (-not ('HvqdStreamHelper' -as [type])) {
        Add-Type @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class HvqdStreamHelper {
    public static void CopyToFile(object comStreamObj, string outputPath) {
        IStream stream = (IStream)comStreamObj;
        byte[]  buf    = new byte[65536];
        IntPtr  pRead  = Marshal.AllocCoTaskMem(sizeof(int));
        try {
            using (var fs = new FileStream(outputPath, FileMode.Create, FileAccess.Write)) {
                int n;
                do {
                    stream.Read(buf, buf.Length, pRead);
                    n = Marshal.ReadInt32(pRead);
                    if (n > 0) fs.Write(buf, 0, n);
                } while (n > 0);
            }
        } finally {
            Marshal.FreeCoTaskMem(pRead);
        }
    }
}
'@
    }

    # ---- Step 1: Write autounattend.xml to a temp folder ----
    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "hvqd-$VMName-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $tmpDir 'autounattend.xml'), $XmlContent, $utf8NoBom)

        # ---- Step 2: Build ISO using IMAPI2FS (built-in Windows COM) ----
        $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fsi.VolumeName          = 'UNATTEND'
        $fsi.FileSystemsToCreate = 4  # FsiFileSystemISO9660
        $fsi.Root.AddTree($tmpDir, $false)

        $resultImage = $fsi.CreateResultImage()

        # ---- Step 3: Copy the image stream to disk via the C# helper ----
        [HvqdStreamHelper]::CopyToFile($resultImage.ImageStream, $isoPath)

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($resultImage) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($fsi)         | Out-Null
    } finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }

    # ---- Step 4: Attach to the VM as a second DVD drive ----
    # Windows Setup scans ALL optical drives for autounattend.xml, so no
    # specific controller slot or boot-order change is needed.
    Add-VMDvdDrive -VMName $VMName -Path $isoPath

    return $isoPath
}
