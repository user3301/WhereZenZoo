#Requires -Version 5.1
<#
.SYNOPSIS
    Main WhereZenZoo setup orchestrator (winget-based).
.DESCRIPTION
    Installs the winget packages declared in config/packages.json and creates the
    dotfile symlinks (Neovim config from the dotfiles submodule, PowerShell profile).

    The run is idempotent: packages that are already installed are skipped, and
    symlinks that already point at the right target are left alone. Packages this
    script installs are recorded in a per-user state file so uninstall.ps1 can
    revert only what was actually installed here.
.PARAMETER All
    Runs every phase. This is the default when no phase flag is supplied.
.PARAMETER Packages
    Installs the winget packages listed in config/packages.json.
.PARAMETER Symlinks
    Creates the Neovim config and PowerShell profile symlinks.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\setup.ps1

    Runs the full setup.
.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\setup.ps1 -Packages

    Installs or refreshes only the winget packages.
.NOTES
    Requires Developer Mode so symlinks can be created without elevation, and
    winget (App Installer). Run bootstrap.ps1 / install.ps1 on a fresh machine.
#>

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Packages,
    [switch]$Symlinks
)

$ErrorActionPreference = 'Stop'
$RepoRoot = $PSScriptRoot

if (-not ($Packages -or $Symlinks)) {
    $All = $true
}

# Maps each winget package id to the command it provides, so an install that was
# made outside winget's knowledge (e.g. portable git on PATH) is still respected.
$PackageCommands = @{
    'Git.Git'                 = 'git'
    'Microsoft.PowerShell'    = 'pwsh'
    'Neovim.Neovim'           = 'nvim'
    'sharkdp.fd'              = 'fd'
    'BurntSushi.ripgrep.MSVC' = 'rg'
    'JesseDuffield.lazygit'   = 'lazygit'
    'ezwinports.make'         = 'make'
    'Starship.Starship'       = 'starship'
    'zig.zig'                 = 'zig'
}

function Write-Phase   { param([string]$Name)    Write-Host "`n===> $Name" -ForegroundColor Cyan }
function Write-Success { param([string]$Message) Write-Host "[ok] $Message" -ForegroundColor Green }
function Write-Skip    { param([string]$Message) Write-Host "[skip] $Message" -ForegroundColor DarkGray }
function Write-Warn    { param([string]$Message) Write-Host "[warn] $Message" -ForegroundColor Yellow }

function Update-SessionPath {
    # Rebuild the current session PATH so tools installed during this run are
    # visible without reopening the terminal. WinGet drops shims into Links.
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $links   = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    $parts   = @($machine, $user, $links) | Where-Object { $_ }
    $env:PATH = ($parts -join ';')
}

function Get-StatePath {
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'WhereZenZoo') 'installed.json')
}

function Add-InstalledPackage {
    param([Parameter(Mandatory)][string]$Id)

    $path = Get-StatePath
    $dir  = Split-Path $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $ids = @()
    if (Test-Path $path) {
        try { $ids = @(Get-Content $path -Raw | ConvertFrom-Json) } catch { $ids = @() }
    }
    if ($ids -notcontains $Id) {
        $ids += $Id
        ConvertTo-Json -InputObject $ids | Set-Content -Path $path -Encoding UTF8
    }
}

function Test-PackageInstalled {
    param([Parameter(Mandatory)][string]$Id)

    # Fast path: the command it provides is already on PATH.
    $cmd = $PackageCommands[$Id]
    if ($cmd -and (Get-Command $cmd -ErrorAction SilentlyContinue)) { return $true }

    # Otherwise ask winget whether the exact id is installed (covers ARP entries).
    winget list --id $Id --exact --accept-source-agreements 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Invoke-ValidatePrerequisites {
    Write-Phase 'Validate prerequisites'

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw 'Windows PowerShell 5.1 or higher is required.'
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not available. Install "App Installer" from the Microsoft Store, then re-run.'
    }
    Write-Success 'winget available'
}

function Invoke-Packages {
    Write-Phase 'Install winget packages'

    $manifest = Get-Content (Join-Path $RepoRoot 'config/packages.json') -Raw | ConvertFrom-Json
    $ids = $manifest.Sources[0].Packages.PackageIdentifier

    foreach ($id in $ids) {
        if (Test-PackageInstalled -Id $id) {
            Write-Skip "$id already installed"
            continue
        }

        Write-Host "[setup] Installing $id..."
        winget install --id $id --exact --source winget --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "winget failed to install $id (exit $LASTEXITCODE)."
        }

        Add-InstalledPackage -Id $id
        Write-Success "$id installed"
    }

    Update-SessionPath
}

function Set-Symlink {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Skip "$Description source missing ($TargetPath) — did the submodule init?"
        return
    }

    $parent = Split-Path $LinkPath
    if ($parent -and -not (Test-Path $parent)) {
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

function Get-ProfilePath {
    # All-hosts CurrentUser profile path for each installed PowerShell edition, so
    # the profile loads in both PowerShell 7 (pwsh) and Windows PowerShell. Each
    # path is queried from the shell itself so OneDrive Documents redirection is
    # resolved correctly.
    $paths = New-Object System.Collections.Generic.List[string]
    $paths.Add($PROFILE.CurrentUserAllHosts)

    $other = if ($PSVersionTable.PSEdition -eq 'Core') { 'powershell.exe' } else { 'pwsh' }
    $cmd = Get-Command $other -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $p = & $cmd.Source -NoProfile -Command '$PROFILE.CurrentUserAllHosts' 2>$null
            if ($p) { $paths.Add(($p | Select-Object -First 1).Trim()) }
        } catch { }
    }

    return ($paths | Where-Object { $_ } | Select-Object -Unique)
}

function Invoke-Symlinks {
    Write-Phase 'Create symlinks'

    # Make sure the dotfiles submodule (which holds the Neovim config) is present.
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git -C $RepoRoot submodule update --init --recursive | Out-Null
    }

    $nvimSrc = Join-Path $RepoRoot 'submodules\dotfiles\nvim\.config\nvim'
    Set-Symlink -LinkPath (Join-Path $env:LOCALAPPDATA 'nvim') -TargetPath $nvimSrc -Description 'Neovim config'

    $profileSrc = Join-Path $RepoRoot 'powershell\profile.ps1'
    foreach ($profilePath in (Get-ProfilePath)) {
        $edition = if ($profilePath -like '*\PowerShell\*') { 'PowerShell 7' } else { 'Windows PowerShell' }
        Set-Symlink -LinkPath $profilePath -TargetPath $profileSrc -Description "$edition profile"
    }
}

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   WhereZenZoo — Setup (winget)     ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

Invoke-ValidatePrerequisites
if ($All -or $Packages) { Invoke-Packages }
if ($All -or $Symlinks) { Invoke-Symlinks }

Write-Host "`nSetup complete. Restart your terminal to load persistent PATH changes."
