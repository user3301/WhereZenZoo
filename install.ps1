#Requires -Version 5.1
<#!
.SYNOPSIS
    Remote installer for WhereZenZoo.
.DESCRIPTION
    Installs Scoop and Git if needed, clones the repository, then runs bootstrap.ps1.
#>

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/user3301/WhereZenZoo.git'
$InstallUrl = 'https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1'
$CloneDir = Join-Path $env:USERPROFILE 'dotfiles'

function Add-ScoopToPath {
    $paths = @(
        (Join-Path $env:USERPROFILE 'scoop\shims'),
        (Join-Path $env:USERPROFILE 'scoop\apps\git\current\cmd')
    ) | Where-Object { Test-Path $_ }

    foreach ($path in $paths) {
        if (($env:PATH -split ';') -notcontains $path) {
            $env:PATH = "$path;$env:PATH"
        }
    }
}

function Install-ScoopIfMissing {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host '[install] Scoop already available.'
        return
    }

    Write-Host '[install] Installing Scoop...'
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Add-ScoopToPath

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw 'Scoop installation completed, but scoop is not on PATH. Open a new terminal and re-run the installer.'
    }
}

Write-Host "[install] Running under PowerShell $($PSVersionTable.PSVersion)"

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Do not run this installer as Administrator. Scoop is a per-user package manager.'
}

Install-ScoopIfMissing
Add-ScoopToPath

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '[install] Installing Git with Scoop...'
    scoop install git
    Add-ScoopToPath
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was installed but is not available on PATH. Open a new terminal and re-run the installer.'
}

if (Test-Path (Join-Path $CloneDir '.git')) {
    Write-Host "[install] Updating existing clone at $CloneDir..."
    git -C $CloneDir pull --ff-only
} elseif (Test-Path $CloneDir) {
    throw "'$CloneDir' already exists but is not a git repository. Move it aside and re-run."
} else {
    Write-Host "[install] Cloning WhereZenZoo to $CloneDir..."
    git clone $RepoUrl $CloneDir
}

$bootstrap = Join-Path $CloneDir 'bootstrap.ps1'
Write-Host '[install] Handing off to bootstrap.ps1...'
& powershell.exe -ExecutionPolicy Bypass -File $bootstrap
exit $LASTEXITCODE
