#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstraps the WhereZenZoo setup from a local clone.
.DESCRIPTION
    Ensures winget and Git are present, initialises the dotfiles submodule, then
    runs setup.ps1. Use this after cloning the repo manually; install.ps1 calls it
    for you on a fresh machine.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\bootstrap.ps1
.NOTES
    This script has no parameters. Requires Developer Mode (for symlinks) and winget.
#>

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $links   = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $parts   = @($machine, $user, $links) | Where-Object { $_ }
    $env:PATH = ($parts -join ';')
}

Write-Host '[bootstrap] Starting WhereZenZoo bootstrap...'

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not available. Install "App Installer" from the Microsoft Store, then re-run.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '[bootstrap] Installing Git with winget...'
    winget install --id Git.Git --exact --source winget --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    Update-SessionPath
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was installed but is not on PATH yet. Open a new terminal and re-run bootstrap.ps1.'
}

Write-Host '[bootstrap] Updating dotfiles submodule...'
git -C $RepoRoot submodule update --init --recursive

$setup = Join-Path $RepoRoot 'setup.ps1'
Write-Host '[bootstrap] Running setup.ps1...'
& powershell.exe -ExecutionPolicy Bypass -File $setup
exit $LASTEXITCODE
