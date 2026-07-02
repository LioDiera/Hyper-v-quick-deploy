@{
    Name             = 'Windows Server 2016'
    OsCode           = 'WS16'
    Generation       = 2
    MemoryStartupMB  = 1024
    MemoryMinimumMB  = 512
    MemoryMaximumMB  = 2048
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('DJ', 'WG')
    KmsKey           = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY'  # WS 2016 Standard -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows Server 2016 Standard (Desktop Experience)'
    WimImageIndex    = 2   # index in install.wim: 1=Standard Core, 2=Standard DE, 3=Datacenter Core, 4=Datacenter DE
    Editions         = @(
        @{ Name = 'Standard (Desktop Experience)';   WimImageIndex = 2; WimImageName = 'Windows Server 2016 Standard (Desktop Experience)';   KmsKey = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY' }
        @{ Name = 'Standard Core';                   WimImageIndex = 1; WimImageName = 'Windows Server 2016 Standard';                        KmsKey = 'WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY' }
        @{ Name = 'Datacenter (Desktop Experience)'; WimImageIndex = 4; WimImageName = 'Windows Server 2016 Datacenter (Desktop Experience)'; KmsKey = 'CB7KF-BWN84-R7R2Y-793K2-8XDDG' }
        @{ Name = 'Datacenter Core';                 WimImageIndex = 3; WimImageName = 'Windows Server 2016 Datacenter';                      KmsKey = 'CB7KF-BWN84-R7R2Y-793K2-8XDDG' }
    )
}
