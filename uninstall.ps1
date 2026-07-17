#Requires -Version 7.0
<#
.SYNOPSIS
    Removes WhereZenZoo symlinks, modules, and Scoop packages.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$All,
    [switch]$Symlinks,
    [switch]$Shell,
    [switch]$Packages
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

if (-not ($Symlinks -or $Shell -or $Packages -or $All)) {
    $Symlinks = $true
    $Shell = $true
    $Packages = $true
}
if ($All) {
    $Symlinks = $true
    $Shell = $true
    $Packages = $true
}

function Write-Phase { param([string]$Name) Write-Host "`n===> $Name" -ForegroundColor Cyan }
function Write-Done { param([string]$Message) Write-Host "[removed] $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "[skip] $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }

function Remove-Symlink {
    param([string]$LinkPath, [string]$Description)

    if (-not (Test-Path $LinkPath)) {
        Write-Skip "$Description not found"
        return
    }

    $item = Get-Item $LinkPath -Force
    if ($item.LinkType -ne 'SymbolicLink') {
        Write-Warn "$Description at $LinkPath is not a symlink; skipping"
        return
    }

    Remove-Item $LinkPath -Force -Recurse
    Write-Done "$Description symlink"

    $backup = "$LinkPath.bak"
    if (Test-Path $backup) {
        Rename-Item $backup $LinkPath -Force
        Write-Host "[restored] $Description backup restored"
    }
}

function Invoke-RemoveSymlinks {
    Write-Phase 'Remove symlinks'
    Remove-Symlink -LinkPath $PROFILE.CurrentUserAllHosts -Description 'PowerShell profile'
    Remove-Symlink -LinkPath (Join-Path $env:USERPROFILE '.config\fastfetch') -Description 'fastfetch config'
}

function Invoke-RemoveModules {
    Write-Phase 'Remove PowerShell modules'
    $config = Get-Content (Join-Path $RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json

    foreach ($module in $config.modules) {
        if (Get-Module -ListAvailable -Name $module.name) {
            Uninstall-Module -Name $module.name -AllVersions -Force -ErrorAction SilentlyContinue
            Write-Done $module.name
        } else {
            Write-Skip "$($module.name) not installed"
        }
    }
}

function Invoke-RemovePackages {
    Write-Phase 'Remove Scoop packages'
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Skip 'Scoop not available'
        return
    }

    $config = Get-Content (Join-Path $RepoRoot 'config/scoop.json') -Raw | ConvertFrom-Json
    foreach ($package in @($config.packages | Sort-Object -Descending)) {
        $installed = scoop list 2>$null | Select-String -Pattern "^$([regex]::Escape($package))\s"
        if ($installed) {
            scoop uninstall $package
            Write-Done $package
        } else {
            Write-Skip "$package not installed"
        }
    }
}

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   WhereZenZoo — Uninstall          ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

if ($Symlinks) { Invoke-RemoveSymlinks }
if ($Shell) { Invoke-RemoveModules }
if ($Packages) { Invoke-RemovePackages }

Write-Host "`nUninstall complete. Scoop itself was left installed."
