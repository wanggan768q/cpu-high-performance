#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$entryScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'cpu-high-performance.ps1'
if (-not (Test-Path -Path $entryScriptPath)) {
    throw "Unable to find '$entryScriptPath'."
}

& $entryScriptPath -Action Apply -WhatIf:$WhatIfPreference
