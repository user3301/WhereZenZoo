#Requires -Version 5.1
<#
.SYNOPSIS
    Reverts a WhereZenZoo setup.
.DESCRIPTION
    Removes the symlinks created by setup.ps1 and uninstalls only the winget
    packages that setup.ps1 actually installed, as recorded in the per-user
    state file. Tools that were already present before setup ran are never
    removed.

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
# Don't let PowerShell 7.4+ turn a benign non-zero winget exit into a
# terminating error; we check $LASTEXITCODE ourselves.
$PSNativeCommandUseErrorActionPreference = $false

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

function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $links   = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $parts   = @($machine, $user, $links) | Where-Object { $_ }
    $env:PATH = ($parts -join ';')
}

function Get-PowerShell7ProfilePath {
    # Match setup.ps1: query pwsh so OneDrive KFR / Known Folder redirection is
    # reflected in the CurrentUserCurrentHost path.
    Update-SessionPath

    if ($PSVersionTable.PSEdition -eq 'Core') {
        return $PROFILE.CurrentUserCurrentHost
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        return $null
    }

    $path = & $pwsh.Source -NoProfile -Command '$PROFILE.CurrentUserCurrentHost' 2>$null
    if ($path) {
        return ($path | Select-Object -First 1).Trim()
    }

    return $null
}

function Remove-Symlink {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [string]$TargetPath,
        [string]$TargetSuffix,
        [Parameter(Mandatory)][string]$Description
    )

    $item = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Skip "$Description not found"
        return
    }

    if ($item.LinkType -ne 'SymbolicLink') {
        Write-Warn "$Description at $LinkPath is not a symlink; leaving it alone"
        return
    }

    $target = ($item.Target | Select-Object -First 1)
    $matchesExpectedTarget = $false
    if ($target -and $TargetPath) {
        $resolvedTarget = if ([System.IO.Path]::IsPathRooted($target)) {
            [System.IO.Path]::GetFullPath($target)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $item.DirectoryName $target))
        }
        $expectedTarget = [System.IO.Path]::GetFullPath($TargetPath)
        $matchesExpectedTarget = [string]::Equals(
            $resolvedTarget.TrimEnd('\', '/'),
            $expectedTarget.TrimEnd('\', '/'),
            [System.StringComparison]::OrdinalIgnoreCase
        )
    } elseif ($target -and $TargetSuffix) {
        $matchesExpectedTarget = $target -like "*$TargetSuffix"
    }

    if (-not $matchesExpectedTarget) {
        Write-Warn "$Description points at $target (not a WhereZenZoo target); leaving it alone"
        return
    }

    # Delete only the reparse point. Remove-Item -Recurse on a directory symlink can
    # delete the TARGET's contents on PowerShell 5.1, so delete the link directly.
    if ($item -is [System.IO.DirectoryInfo]) {
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

    $profilePath = Get-PowerShell7ProfilePath
    if ($profilePath) {
        Remove-Symlink -LinkPath $profilePath `
            -TargetSuffix 'powershell\profile.ps1' -Description 'PowerShell 7 CurrentUserCurrentHost profile'
    } else {
        Write-Skip 'PowerShell 7 profile path could not be resolved'
    }

    $repoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $HOME 'dotfiles' }
    Remove-Symlink -LinkPath (Join-Path $HOME 'powershell') `
        -TargetPath (Join-Path $repoRoot 'powershell') -Description 'PowerShell directory'
    Remove-Symlink -LinkPath (Join-Path $env:USERPROFILE '.config\git') `
        -TargetSuffix 'git\.config\git' -Description 'Git config'
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
    try { $ids = @(Get-Content $statePath -Raw | ConvertFrom-Json | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Unique) } catch { $ids = @() }
    if (-not $ids) {
        Write-Skip 'Install record is empty'
        Remove-Item $statePath -Force -ErrorAction SilentlyContinue
        return
    }

    $failed = @()
    foreach ($rawId in $ids) {
        # Records from older runs may carry stray whitespace, which makes the id
        # fail to match what winget has installed. Normalize before using it.
        $id = "$rawId".Trim()
        if (-not $id) { continue }

        Write-Host "[uninstall] Removing $id..."
        winget uninstall --id $id --exact --silent --disable-interactivity 2>$null

        # Judge success by absence, not the exit code: winget returns non-zero
        # when the package isn't installed ("No installed package found"), which
        # for an uninstall is exactly the outcome we want.
        winget list --id $id --exact --accept-source-agreements 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Warn "$id is still installed after uninstall; keeping it in the record"
            $failed += $id
        } else {
            Write-Done $id
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
