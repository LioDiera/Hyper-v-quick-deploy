@{
    # Module identity
    ModuleVersion     = '1.0.0'
    GUID              = '4a3b2c1d-0e5f-4a7b-8c9d-1e2f3a4b5c6d'
    Author            = 'Hyper-V Quick Deploy'
    Description       = 'Rapidly deploy Hyper-V VMs from ISO images using a polished terminal TUI.'
    PowerShellVersion = '5.1'

    # Root module that contains Start-HVQuickDeploy
    RootModule        = 'HyperVQuickDeploy.psm1'

    # Only export the public entry points — internal helpers stay private
    FunctionsToExport = @('Start-HVQuickDeploy', 'Edit-HVQDProductKeys')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    # Hyper-V cmdlets must be available; this will surface a clear error if
    # the module is imported on a machine without Hyper-V installed.
    RequiredModules   = @(
        @{ ModuleName = 'Hyper-V'; ModuleVersion = '2.0.0.0' }
    )

    PrivateData = @{
        PSData = @{
            Tags       = @('HyperV', 'VM', 'Deploy', 'TUI')
            ProjectUri = 'https://github.com/your-repo/hyper-v-quick-deploy'
        }
    }
}
