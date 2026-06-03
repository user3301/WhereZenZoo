#Requires -Version 7.0
<#
.SYNOPSIS
    Uninstall script — reverses everything setup.ps1 and bootstrap.ps1 applied.

.DESCRIPTION
    Removes symlinks (restoring .bak backups where they exist), uninstalls
    PowerShell modules, removes Meslo Nerd Font files and their registry
    entries, and optionally uninstalls WinGet packages.

    All phases run by default. Pass individual flags to run a subset.

.PARAMETER All
    Run all phases including package uninstallation.

.PARAMETER Packages
    Phase 3: Uninstall WinGet packages installed by setup.ps1 / bootstrap.ps1.

.PARAMETER Symlinks
    Phase 1: Remove symlinks and restore backups.

.PARAMETER Shell
    Phase 2: Uninstall PowerShell modules.

.PARAMETER Fonts
    Phase 4: Remove Meslo Nerd Font files and registry entries.

.NOTES
    Run as: pwsh -ExecutionPolicy Bypass -File uninstall.ps1
    Some steps (font removal, package uninstall) require Administrator.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$All,
    [switch]$Symlinks,
    [switch]$Shell,
    [switch]$Packages,
    [switch]$Fonts
)

$ErrorActionPreference = 'Stop'

# If no flags passed, run all phases
if (-not ($Symlinks -or $Shell -or $Packages -or $Fonts -or $All)) {
    $Symlinks = $true
    $Shell    = $true
    $Packages = $true
    $Fonts    = $true
}
if ($All) {
    $Symlinks = $true
    $Shell    = $true
    $Packages = $true
    $Fonts    = $true
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Phase {
    param([string]$Name)
    Write-Host ""
    Write-Host "===> $Name" -ForegroundColor Cyan
}

function Write-Done {
    param([string]$Message)
    Write-Host "[removed] $Message" -ForegroundColor Green
}

function Write-Restored {
    param([string]$Message)
    Write-Host "[restored] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[skip] $Message" -ForegroundColor DarkGray
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Remove-Symlink {
    param(
        [string]$LinkPath,
        [string]$Description
    )

    if (-not (Test-Path $LinkPath)) {
        Write-Skip "$Description — not found"
        return
    }

    $item = Get-Item $LinkPath -Force
    if ($item.LinkType -ne 'SymbolicLink') {
        Write-Warn "$Description at '$LinkPath' is not a symlink — skipping to avoid data loss"
        return
    }

    Remove-Item $LinkPath -Force -Recurse -ErrorAction SilentlyContinue
    Write-Done "$Description symlink removed"

    # Restore backup if one exists
    $backup = "$LinkPath.bak"
    if (Test-Path $backup) {
        Rename-Item $backup $LinkPath -Force
        Write-Restored "$Description restored from backup"
    }
}

# ---------------------------------------------------------------------------
# Phase 1: Remove symlinks
# ---------------------------------------------------------------------------

function Invoke-RemoveSymlinks {
    Write-Phase 'Phase 1: Remove symlinks'

    # PowerShell profile
    Remove-Symlink -LinkPath $PROFILE.CurrentUserAllHosts -Description 'PowerShell profile'

    # Neovim config
    Remove-Symlink -LinkPath "$env:LOCALAPPDATA\nvim" -Description 'Neovim config'

    # Git config
    Remove-Symlink -LinkPath "$env:USERPROFILE\.config\git" -Description 'Git config'

    Write-Warn '~/.gitconfig was deleted by setup.ps1 without a backup and cannot be auto-restored.'
    Write-Warn 'Recreate it manually if needed: git config --global user.name "..." --global user.email "..."'

    # Zellij config
    Remove-Symlink -LinkPath "$env:APPDATA\Zellij\config\config.kdl" -Description 'Zellij config'

    # Fastfetch config
    Remove-Symlink -LinkPath "$env:USERPROFILE\.config\fastfetch" -Description 'Fastfetch config'
}

# ---------------------------------------------------------------------------
# Phase 2: Uninstall PowerShell modules
# ---------------------------------------------------------------------------

function Invoke-UninstallModules {
    Write-Phase 'Phase 2: Uninstall PowerShell modules'

    $modulesFile = Join-Path $PSScriptRoot 'powershell/modules.json'
    $cfg = Get-Content $modulesFile | ConvertFrom-Json

    foreach ($mod in $cfg.modules) {
        if (Get-Module -ListAvailable -Name $mod.name) {
            Write-Host "[uninstall] Removing module $($mod.name)..."
            Uninstall-Module -Name $mod.name -AllVersions -Force -ErrorAction SilentlyContinue
            Write-Done "$($mod.name) uninstalled"
        } else {
            Write-Skip "$($mod.name) not installed"
        }
    }

    # Remove SHELL env var set by setup.ps1 for zellij
    if ([System.Environment]::GetEnvironmentVariable('SHELL', 'User') -eq 'pwsh') {
        [System.Environment]::SetEnvironmentVariable('SHELL', $null, 'User')
        Write-Done 'SHELL user environment variable removed'
    } else {
        Write-Skip 'SHELL not set by this setup — skipping'
    }
}

# ---------------------------------------------------------------------------
# Phase 3: Uninstall WinGet packages
# ---------------------------------------------------------------------------

function Invoke-UninstallPackages {
    Write-Phase 'Phase 3: Uninstall WinGet packages'

    # Packages installed by bootstrap.ps1 + setup.ps1
    $packages = @(
        @{ Id = 'BurntSushi.ripgrep.MSVC';        Name = 'ripgrep'      },
        @{ Id = 'Fastfetch-cli.Fastfetch';         Name = 'fastfetch'    },
        @{ Id = 'JanDeDobbeleer.OhMyPosh';        Name = 'Oh My Posh'   },
        @{ Id = 'JesseDuffield.lazygit';           Name = 'lazygit'      },
@{ Id = 'Neovim.Neovim';                   Name = 'Neovim'       },
        @{ Id = 'sharkdp.fd';                      Name = 'fd'           },
        @{ Id = 'Zellij.Zellij';                   Name = 'Zellij'       },
        @{ Id = 'Casey.Just';                      Name = 'just'         },
        @{ Id = 'Git.Git';                         Name = 'Git'          },
        @{ Id = 'Microsoft.PowerShell';            Name = 'PowerShell 7' }
    )

    foreach ($pkg in $packages) {
        Write-Host "[uninstall] Removing $($pkg.Name) ($($pkg.Id))..."
        winget uninstall --id $pkg.Id --exact --silent --disable-interactivity 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Done "$($pkg.Name) uninstalled"
        } else {
            Write-Skip "$($pkg.Name) — not installed or already removed"
        }
    }
}

# ---------------------------------------------------------------------------
# Phase 4: Remove Meslo Nerd Font
# ---------------------------------------------------------------------------

function Invoke-RemoveFonts {
    Write-Phase 'Phase 4: Remove Meslo Nerd Font'

    $fontsDir = "$env:USERPROFILE\AppData\Local\Microsoft\Windows\Fonts"
    $regPath  = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

    $fontFiles = Get-ChildItem "$fontsDir\MesloLGM*NerdFont*.ttf" -ErrorAction SilentlyContinue

    if (-not $fontFiles) {
        Write-Skip 'No Meslo Nerd Font files found'
        return
    }

    $shell  = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace($fontsDir)

    foreach ($file in $fontFiles) {
        # Remove registry entry
        $item     = $folder.ParseName($file.Name)
        $fontName = $folder.GetDetailsOf($item, 21)
        if (-not $fontName) { $fontName = $folder.GetDetailsOf($item, 0) }
        $regKey = "$fontName (TrueType)"
        if ($fontName -and (Get-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue)) {
            Remove-ItemProperty -Path $regPath -Name $regKey -Force -ErrorAction SilentlyContinue
        }

        # Remove font file
        Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        Write-Done "Font removed: $($file.Name)"
    }
}

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   Windows 11 Dotfiles — Uninstall  ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

if ($Symlinks) { Invoke-RemoveSymlinks  }
if ($Shell)    { Invoke-UninstallModules }
if ($Packages) { Invoke-UninstallPackages }
if ($Fonts)    { Invoke-RemoveFonts     }

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   Uninstall complete!              ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''
