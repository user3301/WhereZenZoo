#Requires -Version 5.1
<#
.SYNOPSIS
    Remote bootstrapper — no git required. Download and run directly:

    irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1 | iex

.DESCRIPTION
    1. Self-elevates to Administrator (re-downloads to a temp file if needed).
    2. Installs Git via winget.
    3. Clones the repo to $env:USERPROFILE\dotfiles (or pulls if already present).
    4. Hands off to bootstrap.ps1 for the rest of the setup.
#>

$ErrorActionPreference = 'Stop'

$REPO_URL    = 'https://github.com/user3301/WhereZenZoo.git'
$INSTALL_URL = 'https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1'
$CLONE_DIR   = "$env:USERPROFILE\dotfiles"
$GIT_ID      = 'Git.Git'
$WINGET_OK   = 0, -1978335219, -1978335189   # success / already-installed / already-latest

# ── Self-elevate ─────────────────────────────────────────────────────────────
# When piped through irm|iex there is no script file on disk, so we cannot
# pass $MyInvocation.MyCommand.Path to runas. Re-download to a temp file and
# re-launch that file elevated instead.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[install] Elevating to Administrator...'
    $tmp = "$env:TEMP\wzz-install-$(Get-Random).ps1"
    (New-Object System.Net.WebClient).DownloadFile($INSTALL_URL, $tmp)
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$tmp`"" -Verb RunAs -Wait
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    exit $LASTEXITCODE
}

Write-Host "[install] Running as Administrator under PowerShell $($PSVersionTable.PSVersion)"

# ── Ensure winget is available ───────────────────────────────────────────────
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host '[install] ERROR: winget is not available. Install App Installer from the Microsoft Store and re-run.' -ForegroundColor Red
    exit 1
}

# ── Install git if missing ───────────────────────────────────────────────────
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Host '[install] git already available — skipping install.'
} else {
    Write-Host '[install] Installing Git via winget...'
    winget install --id $GIT_ID --exact --silent --accept-source-agreements --accept-package-agreements
    $rc = $LASTEXITCODE
    if ($rc -notin $WINGET_OK) {
        Write-Host "[install] ERROR: winget exited $rc — git install failed." -ForegroundColor Red
        exit $rc
    }

    # Refresh PATH in this session so git is immediately visible.
    $env:PATH = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host '[install] ERROR: git not found after install. Open a new terminal and re-run.' -ForegroundColor Red
        exit 1
    }
    Write-Host '[install] Git installed.'
}

# ── Clone or update the repo ─────────────────────────────────────────────────
if (Test-Path (Join-Path $CLONE_DIR '.git')) {
    Write-Host "[install] Repo already present at $CLONE_DIR — pulling latest..."
    git -C "$CLONE_DIR" pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[install] ERROR: git pull failed (exit $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
} elseif (Test-Path $CLONE_DIR) {
    Write-Host "[install] ERROR: '$CLONE_DIR' already exists but is not a git repo. Remove it and re-run." -ForegroundColor Red
    exit 1
} else {
    Write-Host "[install] Cloning repo to $CLONE_DIR..."
    git clone "$REPO_URL" "$CLONE_DIR"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[install] ERROR: git clone failed (exit $LASTEXITCODE)." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# ── Hand off to bootstrap.ps1 ────────────────────────────────────────────────
$bootstrap = Join-Path $CLONE_DIR 'bootstrap.ps1'
Write-Host '[install] Handing off to bootstrap.ps1...'
& powershell.exe -ExecutionPolicy Bypass -File $bootstrap
exit $LASTEXITCODE
