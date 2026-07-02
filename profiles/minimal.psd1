@{
    # Generation 1 and a single JoinType — the join-type picker screen is
    # automatically skipped and 'WG' is selected without user input.
    # SecureBoot and TPM are not available on Gen1 VMs.
    Name             = 'Minimal'
    OsCode           = 'MIN'
    Generation       = 1
    MemoryStartupMB  = 512
    MemoryMinimumMB  = 256
    MemoryMaximumMB  = 1024
    ProcessorCount   = 1
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('WG')
    KmsKey           = ''   # generic profile -- no assumed OS; user supplies appropriate ISO
    WimImageName     = ''   # no assumed edition; Setup will show image picker if ISO has multiple
}
