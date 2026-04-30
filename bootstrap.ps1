#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap script for dotfiles setup. Ensures PowerShell 7 is installed,
    then re-launches itself under pwsh so all subsequent phases run on PS7.

.DESCRIPTION
    Designed to be invoked from a fresh Windows 11 machine under Windows
    PowerShell 5.1. Safe to run multiple times (idempotent).

.NOTES
    Run as: powershell.exe -ExecutionPolicy Bypass -File bootstrap.ps1
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Self-elevate if not running as Administrator
# ---------------------------------------------------------------------------

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[bootstrap] Not running as Administrator — re-launching elevated...'
    $shell = (Get-Process -Id $PID).Path
    Start-Process $shell -ArgumentList "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs -Wait
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$PWSH_WINGET_ID      = 'Microsoft.PowerShell'
$PWSH_DEFAULT_PATH   = "$env:ProgramFiles\PowerShell\7\pwsh.exe"

$JUST_WINGET_ID      = 'Casey.Just'

# WinGet result codes
$WINGET_SUCCESS           = 0
$WINGET_ALREADY_INSTALLED = -1978335219   # 0x8A15002D — package already installed
$WINGET_NO_UPGRADE        = -1978335189   # 0x8A15004B — already on latest version

# ---------------------------------------------------------------------------
# Helper: install a package via winget, treating "already installed" as success
# ---------------------------------------------------------------------------

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )
    Write-Host "[bootstrap] Installing $Name..."
    winget install --id $Id --exact --silent --accept-source-agreements --accept-package-agreements
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne $WINGET_SUCCESS -and $exitCode -ne $WINGET_ALREADY_INSTALLED -and $exitCode -ne $WINGET_NO_UPGRADE) {
        Write-Host "[bootstrap] ERROR: winget exited with code $exitCode. Failed to install $Name." -ForegroundColor Red
        exit $exitCode
    }
    Write-Host "[bootstrap] $Name ready."
}

# ---------------------------------------------------------------------------
# Helper: locate pwsh.exe — checks PATH first, then the standard install dir
# ---------------------------------------------------------------------------

function Find-Pwsh {
    $inPath = Get-Command -Name 'pwsh' -ErrorAction SilentlyContinue
    if ($inPath) {
        return $inPath.Source
    }
    if (Test-Path -LiteralPath $PWSH_DEFAULT_PATH) {
        return $PWSH_DEFAULT_PATH
    }
    return $null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host '[bootstrap] Starting dotfiles bootstrap...'
Write-Host "[bootstrap] Running under PowerShell $($PSVersionTable.PSVersion)"

$pwshExe = Find-Pwsh

if ($pwshExe) {
    # -----------------------------------------------------------------------
    # PS7 is already present
    # -----------------------------------------------------------------------
    Write-Host "[bootstrap] PowerShell 7 found at: $pwshExe"

    # If we are already running inside PS7, install remaining meta-tools then hand off to setup.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        Write-Host '[bootstrap] Running under PowerShell 7. Installing meta-tools...'
        Install-WingetPackage -Id $JUST_WINGET_ID -Name 'just'

        Write-Host '[bootstrap] Handing off to setup.ps1...'
        $setupScript = Join-Path $PSScriptRoot 'setup.ps1'
        & $pwshExe -ExecutionPolicy Bypass -File $setupScript
        exit $LASTEXITCODE
    }

    # We are still in PS5.1 but PS7 exists — re-launch under pwsh now.
    Write-Host '[bootstrap] Re-launching bootstrap under PowerShell 7...'
    $scriptPath = $MyInvocation.MyCommand.Path
    & $pwshExe -ExecutionPolicy Bypass -File $scriptPath
    exit $LASTEXITCODE

} else {
    # -----------------------------------------------------------------------
    # PS7 is not installed — install via winget
    # -----------------------------------------------------------------------
    Write-Host '[bootstrap] PowerShell 7 not found. Installing via winget...'

    # Ensure winget is reachable (it ships with Windows 11 but may be absent
    # on Server or heavily stripped SKUs).
    if (-not (Get-Command -Name 'winget' -ErrorAction SilentlyContinue)) {
        Write-Host '[bootstrap] ERROR: winget is not available on this system. Install the App Installer package from the Microsoft Store and re-run.' -ForegroundColor Red
        exit 1
    }

    Install-WingetPackage -Id $PWSH_WINGET_ID -Name 'PowerShell 7'

    # PATH is not refreshed in the current session after winget installs;
    # fall back to the well-known default location.
    $pwshExe = Find-Pwsh
    if (-not $pwshExe) {
        # Last-resort: the default path should exist even if Find-Pwsh missed it.
        if (Test-Path -LiteralPath $PWSH_DEFAULT_PATH) {
            $pwshExe = $PWSH_DEFAULT_PATH
        } else {
            Write-Host "[bootstrap] ERROR: pwsh.exe not found at '$PWSH_DEFAULT_PATH' after installation. Please open a new terminal and re-run bootstrap.ps1." -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "[bootstrap] Re-launching bootstrap under PowerShell 7 at: $pwshExe"
    $scriptPath = $MyInvocation.MyCommand.Path
    & $pwshExe -ExecutionPolicy Bypass -File $scriptPath
    exit $LASTEXITCODE
}
