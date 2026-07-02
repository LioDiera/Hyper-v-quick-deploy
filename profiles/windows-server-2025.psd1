@{
    Name             = 'Windows Server 2025'
    OsCode           = 'WS25'
    Generation       = 2
    MemoryStartupMB  = 2048
    MemoryMinimumMB  = 1024
    MemoryMaximumMB  = 4096
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('DJ', 'WG')
    KmsKey           = 'TVRH6-WHNXV-R9WG3-9XRFY-MY832'  # WS 2025 Standard -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows Server 2025 Standard (Desktop Experience)'
    WimImageIndex    = 2   # index in install.wim: 1=Standard Core, 2=Standard DE, 3=Datacenter Core, 4=Datacenter DE
    Editions         = @(
        @{ Name = 'Standard (Desktop Experience)';   WimImageIndex = 2; WimImageName = 'Windows Server 2025 Standard (Desktop Experience)';   KmsKey = 'TVRH6-WHNXV-R9WG3-9XRFY-MY832' }
        @{ Name = 'Standard Core';                   WimImageIndex = 1; WimImageName = 'Windows Server 2025 Standard';                        KmsKey = 'TVRH6-WHNXV-R9WG3-9XRFY-MY832' }
        @{ Name = 'Datacenter (Desktop Experience)'; WimImageIndex = 4; WimImageName = 'Windows Server 2025 Datacenter (Desktop Experience)'; KmsKey = 'D764K-2NDRG-47T6Q-P8T8W-YP6DF' }
        @{ Name = 'Datacenter Core';                 WimImageIndex = 3; WimImageName = 'Windows Server 2025 Datacenter';                      KmsKey = 'D764K-2NDRG-47T6Q-P8T8W-YP6DF' }
    )
}
