@{
    Name             = 'Ubuntu Server'
    OsCode           = 'UBU'
    Generation       = 2
    MemoryStartupMB  = 1024
    MemoryMinimumMB  = 512
    MemoryMaximumMB  = 2048
    ProcessorCount   = 2
    SecureBoot       = $false
    TPM              = $false
    JoinTypes        = @('DJ', 'WG')
    KmsKey           = ''   # not applicable -- Ubuntu does not use Windows answer files
    WimImageName     = ''   # unattended install for Ubuntu deferred to v2 (requires cloud-init)
}
