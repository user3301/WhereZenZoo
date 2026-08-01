#Requires -Version 5.1
<#
.SYNOPSIS
    Remote installer for WhereZenZoo (winget-based).
.DESCRIPTION
    Ensures winget and Git are available, clones this repository (with the dotfiles
    submodule) to ~\dotfiles, then hands off to bootstrap.ps1. Safe to re-run: an
    existing clone is fast-forwarded instead of re-cloned.
.EXAMPLE
    irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1 | iex

    Downloads and runs the installer.
.NOTES
    Prerequisites: Developer Mode enabled (for unprivileged symlinks) and winget
    (App Installer). Run from Windows PowerShell.
#>

$ErrorActionPreference = 'Stop'
# Don't let PowerShell 7.4+ turn a benign non-zero winget/git exit into a
# terminating error; we check $LASTEXITCODE / command presence ourselves.
$PSNativeCommandUseErrorActionPreference = $false

$RepoUrl  = 'https://github.com/user3301/WhereZenZoo.git'
$CloneDir = Join-Path $env:USERPROFILE 'dotfiles'

function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $links   = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $parts   = @($machine, $user, $links) | Where-Object { $_ }
    $env:PATH = ($parts -join ';')
}

Write-Host "[install] Running under PowerShell $($PSVersionTable.PSVersion)"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not available. Install "App Installer" from the Microsoft Store, then re-run.'
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '[install] Installing Git with winget...'
    winget install --id Git.Git --exact --source winget --silent `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    Update-SessionPath
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git was installed but is not on PATH yet. Open a new terminal and re-run the installer.'
}

if (Test-Path (Join-Path $CloneDir '.git')) {
    Write-Host "[install] Updating existing clone at $CloneDir..."
    git -C $CloneDir pull --ff-only
    git -C $CloneDir submodule update --init --recursive
} elseif (Test-Path $CloneDir) {
    throw "'$CloneDir' already exists but is not a git repository. Move it aside and re-run."
} else {
    Write-Host "[install] Cloning WhereZenZoo to $CloneDir..."
    git clone --recurse-submodules $RepoUrl $CloneDir
}

$bootstrap = Join-Path $CloneDir 'bootstrap.ps1'
Write-Host '[install] Handing off to bootstrap.ps1...'
& powershell.exe -ExecutionPolicy Bypass -File $bootstrap
$code = $LASTEXITCODE

if ($code -ne 0) {
    Write-Host "[install] Setup reported errors (exit $code). Check the log under $env:LOCALAPPDATA\WhereZenZoo, fix the cause, and re-run." -ForegroundColor Red
} else {
    Write-Host '[install] Done. Open a new terminal to load all changes.' -ForegroundColor Green
}

# Propagate the failure when run as a script file (powershell.exe -File / a
# wrapper), so it can be detected. When run via `irm ... | iex` there is no
# script path, and calling `exit` would close the user's interactive session
# (and its scrollback) — the message above already surfaced the error.
if ($MyInvocation.MyCommand.Path) { exit $code }
