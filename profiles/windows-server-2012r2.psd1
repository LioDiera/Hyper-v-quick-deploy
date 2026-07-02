@{
    # Generation 1 — WS 2012 R2 predates UEFI support in Hyper-V Gen2.
    # SecureBoot and TPM are not available on Gen1 VMs.
    Name             = 'Windows Server 2012 R2'
    OsCode           = 'WS12'
    Generation       = 1
    MemoryStartupMB  = 1024
    MemoryMinimumMB  = 512
    MemoryMaximumMB  = 2048
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('DJ', 'WG')
    KmsKey           = 'D2N9P-3P6X9-2R39C-7RTCD-MDVJX'  # WS 2012 R2 Standard -- KMS client setup key (Microsoft public docs)
    WimImageName     = 'Windows Server 2012 R2 Standard (Server with a GUI)'
    Editions         = @(
        @{ Name = 'Standard (Server with a GUI)';   WimImageName = 'Windows Server 2012 R2 Standard (Server with a GUI)';      KmsKey = 'D2N9P-3P6X9-2R39C-7RTCD-MDVJX' }
        @{ Name = 'Standard Core';                  WimImageName = 'Windows Server 2012 R2 Standard (Server Core Installation)'; KmsKey = 'D2N9P-3P6X9-2R39C-7RTCD-MDVJX' }
        @{ Name = 'Datacenter (Server with a GUI)'; WimImageName = 'Windows Server 2012 R2 Datacenter (Server with a GUI)';    KmsKey = 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9' }
        @{ Name = 'Datacenter Core';                WimImageName = 'Windows Server 2012 R2 Datacenter (Server Core Installation)'; KmsKey = 'W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9' }
    )
}
