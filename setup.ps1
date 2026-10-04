#Requires -Version 7.0
<#
.SYNOPSIS
    Installs Windows tools and connects this clone's PowerShell, Neovim, and Git configs.
.PARAMETER SkipPackages
    Configure dotfiles without calling WinGet.
.PARAMETER PackagesOnly
    Install tools without changing configuration.
.PARAMETER BuildTools
    Also install the optional Visual Studio 2022 C++ workload and Windows SDK.
#>
[CmdletBinding()]
param(
    [switch]$SkipPackages,
    [switch]$PackagesOnly,
    [switch]$BuildTools
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
. (Join-Path $PSScriptRoot 'scripts\common.ps1')
Assert-Windows11
if ($SkipPackages -and ($PackagesOnly -or $BuildTools)) {
    throw '-SkipPackages cannot be combined with -PackagesOnly or -BuildTools.'
}

$configs = Get-Dotfiles -RepoRoot $PSScriptRoot -HomePath $env:USERPROFILE `
    -LocalAppData $env:LOCALAPPDATA -ProfilePath $PROFILE.CurrentUserAllHosts
if (-not $PackagesOnly) {
    Assert-ProfileExecutionPolicy
    foreach ($config in $configs) { Assert-DotfileCanInstall $config }
    $localConfig = Join-Path $env:USERPROFILE '.config\git\config.local'
    $repoLocalConfig = Join-Path $PSScriptRoot 'git\config.local'
    Copy-GitLocalConfig -Source $localConfig -Target $repoLocalConfig -CheckOnly
}

if (-not $SkipPackages) {
    if (-not (Get-Command winget -CommandType Application -ErrorAction Ignore)) {
        throw 'WinGet is required. Install App Installer from the Microsoft Store, then rerun setup.'
    }
    $packages = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\packages.json') -Raw |
        ConvertFrom-Json -AsHashtable
    foreach ($package in $packages) {
        if (-not $package.optional -or $BuildTools) { Install-WinGetPackage $package }
    }
}

if (-not $PackagesOnly) {
    Copy-GitLocalConfig -Source $localConfig -Target $repoLocalConfig
    foreach ($config in $configs) { Install-Dotfile $config }
}

Write-Host 'Setup complete. Open a new PowerShell 7 terminal.' -ForegroundColor Green
