#Requires -Version 5.1
<#!
.SYNOPSIS
    Bootstraps the Scoop-based WhereZenZoo setup.
.DESCRIPTION
    Ensures Scoop, Git, PowerShell 7, and just are installed, then runs setup.ps1 under pwsh.
#>

$ErrorActionPreference = 'Stop'

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

function Install-ScoopIfMissing {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host '[bootstrap] Scoop already available.'
        return
    }

    Write-Host '[bootstrap] Installing Scoop...'
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Add-ScoopToPath
}

function Install-ScoopPackage {
    param([Parameter(Mandatory)][string]$Name)

    $installed = scoop list 2>$null | Select-String -Pattern "^$([regex]::Escape($Name))\s"
    if ($installed) {
        Write-Host "[bootstrap] $Name already installed."
        return
    }

    Write-Host "[bootstrap] Installing $Name..."
    scoop install $Name
}

function Find-Pwsh {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $scoopPwsh = Join-Path $env:USERPROFILE 'scoop\apps\pwsh\current\pwsh.exe'
    if (Test-Path $scoopPwsh) { return $scoopPwsh }

    return $null
}

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Do not run bootstrap.ps1 as Administrator. Scoop is a per-user package manager.'
}

Write-Host '[bootstrap] Starting WhereZenZoo bootstrap...'
Install-ScoopIfMissing
Add-ScoopToPath

foreach ($package in @('git', 'pwsh', 'just')) {
    Install-ScoopPackage -Name $package
    Add-ScoopToPath
}

$pwsh = Find-Pwsh
if (-not $pwsh) {
    throw 'PowerShell 7 was installed but pwsh.exe could not be found.'
}

$setup = Join-Path $PSScriptRoot 'setup.ps1'
Write-Host "[bootstrap] Running setup with $pwsh..."
& $pwsh -ExecutionPolicy Bypass -File $setup
exit $LASTEXITCODE
