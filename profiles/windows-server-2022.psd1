@{
    Name             = 'Windows Server 2022'
    OsCode           = 'WS22'
    Generation       = 2
    MemoryStartupMB  = 2048
    MemoryMinimumMB  = 1024
    MemoryMaximumMB  = 4096
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('DJ', 'WG')
    KmsKey           = 'VDYBN-27WPP-V4HQT-9VMD4-VMK7H'  # WS 2022 Standard -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows Server 2022 Standard (Desktop Experience)'
    WimImageIndex    = 2   # index in install.wim: 1=Standard Core, 2=Standard DE, 3=Datacenter Core, 4=Datacenter DE
    Editions         = @(
        @{ Name = 'Standard (Desktop Experience)';   WimImageIndex = 2; WimImageName = 'Windows Server 2022 Standard (Desktop Experience)';   KmsKey = 'VDYBN-27WPP-V4HQT-9VMD4-VMK7H' }
        @{ Name = 'Standard Core';                   WimImageIndex = 1; WimImageName = 'Windows Server 2022 Standard';                        KmsKey = 'VDYBN-27WPP-V4HQT-9VMD4-VMK7H' }
        @{ Name = 'Datacenter (Desktop Experience)'; WimImageIndex = 4; WimImageName = 'Windows Server 2022 Datacenter (Desktop Experience)'; KmsKey = 'WX4NM-KYWYW-QJJR4-XV3QB-6VM33' }
        @{ Name = 'Datacenter Core';                 WimImageIndex = 3; WimImageName = 'Windows Server 2022 Datacenter';                      KmsKey = 'WX4NM-KYWYW-QJJR4-XV3QB-6VM33' }
    )
}
