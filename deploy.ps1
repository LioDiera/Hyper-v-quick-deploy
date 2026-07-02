# deploy.ps1 — Launcher for Hyper-V Quick Deploy
#
# This script is the only file that legitimately uses $PSScriptRoot.
# It resolves the repo root path and passes it into the module so that
# lib/ files never need to guess their own location.

# Resolve the repo root from this script's own location
$rootPath = $PSScriptRoot

# Import the module fresh each time so changes to .psm1 are picked up
# without needing to open a new PowerShell session.
Import-Module "$rootPath\HyperVQuickDeploy.psm1" -Force

# Start the TUI flow — all screens and logic run inside this call
Start-HVQuickDeploy -RootPath $rootPath
