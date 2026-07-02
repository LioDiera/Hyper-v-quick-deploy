@{
    Name             = 'Windows 11'
    OsCode           = 'W11'
    Generation       = 2
    MemoryStartupMB  = 4096
    MemoryMinimumMB  = 2048
    MemoryMaximumMB  = 8192
    ProcessorCount   = 2
    SecureBoot       = $true
    TPM              = $true
    JoinTypes        = @('EJ', 'HEJ', 'ER', 'DJ', 'WG')
    KmsKey           = 'NPPR9-FWDCX-D2C8J-H872K-2YT43'  # Windows 11 Enterprise -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows 11 Enterprise'            # exact image name in the WIM; user can adjust if ISO differs
    Editions         = @(
        @{ Name = 'Enterprise'; WimImageName = 'Windows 11 Enterprise'; KmsKey = 'NPPR9-FWDCX-D2C8J-H872K-2YT43' }
        @{ Name = 'Pro';        WimImageName = 'Windows 11 Pro';        KmsKey = 'W269N-WFGWX-YVC9B-4J6C9-T83GX' }
        @{ Name = 'Education';  WimImageName = 'Windows 11 Education';  KmsKey = 'NW6C2-QMPVW-D7KKK-3GKT6-VCFB2' }
    )
}
