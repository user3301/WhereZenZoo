#Requires -Version 5.1
<#
.SYNOPSIS
    Reverts a WhereZenZoo setup.
.DESCRIPTION
    Removes the symlinks created by setup.ps1 (restoring any .bak backups) and
    uninstalls only the winget packages that setup.ps1 actually installed, as
    recorded in the per-user state file. Tools that were already present before
    setup ran are never removed.

    Runnable either from a clone or piped straight from the web:
        irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/uninstall.ps1 | iex
.PARAMETER All
    Runs every phase (symlinks + packages). This is the default.
.PARAMETER Symlinks
    Removes the WhereZenZoo symlinks only.
.PARAMETER Packages
    Uninstalls the state-recorded winget packages only.
.PARAMETER Purge
    Additionally removes LazyVim runtime data (%LOCALAPPDATA%\nvim-data) and the
    ~\dotfiles clone (only when not running from inside it).
.NOTES
    Non-symlink files are left untouched to avoid data loss.
#>

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Symlinks,
    [switch]$Packages,
    [switch]$Purge
)

$ErrorActionPreference = 'Stop'

if (-not ($Symlinks -or $Packages)) {
    $All = $true
}

function Write-Phase { param([string]$Name)    Write-Host "`n===> $Name" -ForegroundColor Cyan }
function Write-Done  { param([string]$Message) Write-Host "[removed] $Message" -ForegroundColor Green }
function Write-Skip  { param([string]$Message) Write-Host "[skip] $Message" -ForegroundColor DarkGray }
function Write-Warn  { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }

function Get-StatePath {
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'WhereZenZoo') 'installed.json')
}

function Remove-Symlink {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetSuffix,  # link is ours only if its target ends with this
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path $LinkPath)) {
        Write-Skip "$Description not found"
        return
    }

    $item = Get-Item $LinkPath -Force
    if ($item.LinkType -ne 'SymbolicLink') {
        Write-Warn "$Description at $LinkPath is not a symlink; leaving it alone"
        return
    }

    $target = ($item.Target | Select-Object -First 1)
    if ($target -and ($target -notlike "*$TargetSuffix")) {
        Write-Warn "$Description points at $target (not a WhereZenZoo target); leaving it alone"
        return
    }

    # Delete only the reparse point. Remove-Item -Recurse on a directory symlink can
    # delete the TARGET's contents on PowerShell 5.1, so delete the link directly.
    if ($item.PSIsContainer) {
        [System.IO.Directory]::Delete($item.FullName, $false)
    } else {
        [System.IO.File]::Delete($item.FullName)
    }
    Write-Done "$Description symlink"

    $backup = "$LinkPath.bak"
    if (Test-Path $backup) {
        Rename-Item $backup $LinkPath -Force
        Write-Host "[restored] $Description backup restored"
    }
}

function Invoke-RemoveSymlinks {
    Write-Phase 'Remove symlinks'
    Remove-Symlink -LinkPath (Join-Path $env:LOCALAPPDATA 'nvim') `
        -TargetSuffix 'nvim\.config\nvim' -Description 'Neovim config'
    Remove-Symlink -LinkPath $PROFILE.CurrentUserAllHosts `
        -TargetSuffix 'powershell\profile.ps1' -Description 'PowerShell profile'
}

function Invoke-RemovePackages {
    Write-Phase 'Remove winget packages'

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Skip 'winget not available'
        return
    }

    $statePath = Get-StatePath
    if (-not (Test-Path $statePath)) {
        Write-Skip 'No install record found — nothing installed by WhereZenZoo to remove'
        return
    }

    $ids = @()
    try { $ids = @(Get-Content $statePath -Raw | ConvertFrom-Json) } catch { $ids = @() }
    if (-not $ids) {
        Write-Skip 'Install record is empty'
        Remove-Item $statePath -Force -ErrorAction SilentlyContinue
        return
    }

    $failed = @()
    foreach ($id in $ids) {
        Write-Host "[uninstall] Removing $id..."
        winget uninstall --id $id --exact --silent --disable-interactivity 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Done $id
        } else {
            Write-Warn "winget could not remove $id (exit $LASTEXITCODE)"
            $failed += $id
        }
    }

    if ($failed) {
        ConvertTo-Json -InputObject $failed | Set-Content -Path $statePath -Encoding UTF8
        Write-Warn "Kept $($failed.Count) unremoved package(s) in the install record."
    } else {
        Remove-Item $statePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Purge {
    Write-Phase 'Purge extras'

    $nvimData = Join-Path $env:LOCALAPPDATA 'nvim-data'
    if (Test-Path $nvimData) {
        Remove-Item $nvimData -Recurse -Force -ErrorAction SilentlyContinue
        Write-Done 'LazyVim data (nvim-data)'
    } else {
        Write-Skip 'LazyVim data not found'
    }

    $cloneDir = Join-Path $env:USERPROFILE 'dotfiles'
    $runningFrom = if ($PSScriptRoot) { (Resolve-Path $PSScriptRoot).Path } else { '' }
    if (Test-Path $cloneDir) {
        if ($runningFrom -and ($runningFrom -like "$cloneDir*")) {
            Write-Warn "Not deleting $cloneDir because uninstall is running from inside it."
        } else {
            Remove-Item $cloneDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Done "clone at $cloneDir"
        }
    } else {
        Write-Skip 'Clone directory not found'
    }
}

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   WhereZenZoo — Uninstall          ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

if ($All -or $Symlinks) { Invoke-RemoveSymlinks }
if ($All -or $Packages) { Invoke-RemovePackages }
if ($Purge)             { Invoke-Purge }

Write-Host "`nUninstall complete."
