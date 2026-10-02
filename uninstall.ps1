#Requires -Version 7.0
<#
.SYNOPSIS
    Disconnects this clone's configs and restores their backups.
.DESCRIPTION
    Run from the local clone. Applications, the repository, Neovim runtime data,
    and PowerShell modules are never deleted. Edited or retargeted configs cause
    uninstall to stop rather than remove someone else's changes.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\common.ps1')
Assert-Windows11
$configs = Get-Dotfiles -RepoRoot $PSScriptRoot -HomePath $env:USERPROFILE `
    -LocalAppData $env:LOCALAPPDATA -ProfilePath $PROFILE.CurrentUserAllHosts
foreach ($config in $configs) { Assert-DotfileCanRemove $config }
foreach ($config in $configs) { Remove-Dotfile $config }
Write-Host 'Configs disconnected; backups restored where present. Applications were left installed.' -ForegroundColor Green
