#Requires -Version 7.0
<#!
.SYNOPSIS
    Main WhereZenZoo setup orchestrator.
.DESCRIPTION
    Installs Scoop packages, creates symlinks, and installs PowerShell modules.
#>

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Packages,
    [switch]$Symlinks,
    [switch]$Shell
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

if (-not ($Packages -or $Symlinks -or $Shell)) {
    $All = $true
}

function Write-Phase { param([string]$Name) Write-Host "`n===> $Name" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[ok] $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "[skip] $Message" -ForegroundColor DarkGray }

function Add-ScoopToPath {
    $paths = @(
        (Join-Path $env:USERPROFILE 'scoop\shims'),
        (Join-Path $env:USERPROFILE 'scoop\apps\git\current\cmd'),
        (Join-Path $env:USERPROFILE 'scoop\apps\pwsh\current')
    ) | Where-Object { Test-Path $_ }

    foreach ($path in $paths) {
        if (($env:PATH -split ';') -notcontains $path) {
            $env:PATH = "$path;$env:PATH"
        }
    }
}

function Invoke-ValidatePrerequisites {
    Write-Phase 'Validate prerequisites'

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw 'PowerShell 7 or higher is required. Run bootstrap.ps1 first.'
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"

    Add-ScoopToPath
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw 'Scoop is required. Run install.ps1 or bootstrap.ps1 first.'
    }
    Write-Success 'Scoop available'
}

function Invoke-Packages {
    Write-Phase 'Install Scoop packages'

    $config = Get-Content (Join-Path $RepoRoot 'config/scoop.json') -Raw | ConvertFrom-Json

    foreach ($bucket in $config.buckets) {
        $existingBuckets = scoop bucket list 2>$null
        if ($existingBuckets -match "(^|\s)$([regex]::Escape($bucket))(\s|$)") {
            Write-Skip "Bucket $bucket already added"
        } else {
            Write-Host "[setup] Adding Scoop bucket $bucket..."
            scoop bucket add $bucket
            Write-Success "Bucket $bucket added"
        }
    }

    foreach ($package in $config.packages) {
        $installed = scoop list 2>$null | Select-String -Pattern "^$([regex]::Escape($package))\s"
        if ($installed) {
            Write-Skip "$package already installed"
        } else {
            Write-Host "[setup] Installing $package..."
            scoop install $package
            Write-Success "$package installed"
        }
    }

    Add-ScoopToPath
}

function Set-Symlink {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Description
    )

    $parent = Split-Path $LinkPath
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path $LinkPath) {
        $existing = Get-Item $LinkPath -Force
        if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $TargetPath) {
            Write-Skip "$Description already linked"
            return
        }

        Rename-Item $LinkPath "$LinkPath.bak" -Force
        Write-Host "[setup] Existing $Description backed up to $LinkPath.bak"
    }

    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
    Write-Success "$Description linked"
}

function Invoke-Symlinks {
    Write-Phase 'Create symlinks'

    Set-Symlink -LinkPath $PROFILE.CurrentUserAllHosts -TargetPath (Join-Path $RepoRoot 'powershell/profile.ps1') -Description 'PowerShell profile'
    Set-Symlink -LinkPath (Join-Path $env:USERPROFILE '.config\fastfetch') -TargetPath (Join-Path $RepoRoot 'fastfetch') -Description 'fastfetch config'
}

function Invoke-Shell {
    Write-Phase 'Install PowerShell modules'

    $config = Get-Content (Join-Path $RepoRoot 'powershell/modules.json') -Raw | ConvertFrom-Json
    foreach ($module in $config.modules) {
        if (Get-Module -ListAvailable -Name $module.name) {
            Write-Skip "$($module.name) already installed"
        } else {
            Write-Host "[setup] Installing module $($module.name)..."
            Install-Module -Name $module.name -Scope $module.scope -Force -SkipPublisherCheck
            Write-Success "$($module.name) installed"
        }
    }
}

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   WhereZenZoo — Scoop Setup        ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

Invoke-ValidatePrerequisites
if ($All -or $Packages) { Invoke-Packages }
if ($All -or $Symlinks) { Invoke-Symlinks }
if ($All -or $Shell) { Invoke-Shell }

Write-Host "`nSetup complete. Restart your terminal to load persistent PATH changes."
