@{
    Name             = 'Windows 10'
    OsCode           = 'W10'
    Generation       = 2
    MemoryStartupMB  = 2048
    MemoryMinimumMB  = 1024
    MemoryMaximumMB  = 4096
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('EJ', 'HEJ', 'ER', 'DJ', 'WG')
    KmsKey           = 'NPPR9-FWDCX-D2C8J-H872K-2YT43'  # Windows 10 Enterprise -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows 10 Enterprise'
    Editions         = @(
        @{ Name = 'Enterprise'; WimImageName = 'Windows 10 Enterprise'; KmsKey = 'NPPR9-FWDCX-D2C8J-H872K-2YT43' }
        @{ Name = 'Pro';        WimImageName = 'Windows 10 Pro';        KmsKey = 'W269N-WFGWX-YVC9B-4J6C9-T83GX' }
        @{ Name = 'Education';  WimImageName = 'Windows 10 Education';  KmsKey = 'NW6C2-QMPVW-D7KKK-3GKT6-VCFB2' }
    )
}
