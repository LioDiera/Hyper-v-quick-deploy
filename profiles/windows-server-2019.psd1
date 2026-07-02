@{
    Name             = 'Windows Server 2019'
    OsCode           = 'WS19'
    Generation       = 2
    MemoryStartupMB  = 1024
    MemoryMinimumMB  = 512
    MemoryMaximumMB  = 2048
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('DJ', 'WG')
    KmsKey           = 'N69G4-B89J2-4G8F4-WWYCC-J464C'  # WS 2019 Standard -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows Server 2019 Standard (Desktop Experience)'
    WimImageIndex    = 2   # index in install.wim: 1=Standard Core, 2=Standard DE, 3=Datacenter Core, 4=Datacenter DE
    Editions         = @(
        @{ Name = 'Standard (Desktop Experience)';   WimImageIndex = 2; WimImageName = 'Windows Server 2019 Standard (Desktop Experience)';   KmsKey = 'N69G4-B89J2-4G8F4-WWYCC-J464C' }
        @{ Name = 'Standard Core';                   WimImageIndex = 1; WimImageName = 'Windows Server 2019 Standard';                        KmsKey = 'N69G4-B89J2-4G8F4-WWYCC-J464C' }
        @{ Name = 'Datacenter (Desktop Experience)'; WimImageIndex = 4; WimImageName = 'Windows Server 2019 Datacenter (Desktop Experience)'; KmsKey = 'WMDGN-G9PQG-XVVXX-R3X43-63DFG' }
        @{ Name = 'Datacenter Core';                 WimImageIndex = 3; WimImageName = 'Windows Server 2019 Datacenter';                      KmsKey = 'WMDGN-G9PQG-XVVXX-R3X43-63DFG' }
    )
}
