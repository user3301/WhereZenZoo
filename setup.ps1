#Requires -Version 7.0
<#
.SYNOPSIS
    Main setup orchestrator for Windows 11 dotfiles.

.DESCRIPTION
    Runs all setup phases in order. Each phase is idempotent — safe to re-run.
    Individual phases can be run in isolation using the flags below.

.PARAMETER All
    Run all phases (default behaviour when no flags are passed).

.PARAMETER Packages
    Phase 2: Install WinGet packages and fonts.

.PARAMETER Symlinks
    Phase 3: Create dotfile symlinks (e.g. PowerShell profile stub).

.PARAMETER Shell
    Phase 4: Configure PowerShell profile and prompt.

.NOTES
    Run as: pwsh -ExecutionPolicy Bypass -File setup.ps1
#>

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Packages,
    [switch]$Symlinks,
    [switch]$Shell
)

$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot

# If no flags passed, run everything
if (-not ($Packages -or $Symlinks -or $Shell)) {
    $All = $true
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Phase {
    param([string]$Name)
    Write-Host ""
    Write-Host "===> $Name" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[ok] $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "[skip] $Message" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Phase 1: Validate prerequisites
# ---------------------------------------------------------------------------

function Invoke-ValidatePrerequisites {
    Write-Phase 'Phase 1: Validate prerequisites'

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host '[error] PowerShell 7 or higher is required. Run bootstrap.ps1 first.' -ForegroundColor Red
        exit 1
    }
    Write-Success "PowerShell $($PSVersionTable.PSVersion)"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host '[error] winget is not available. Install App Installer from the Microsoft Store.' -ForegroundColor Red
        exit 1
    }
    Write-Success 'winget available'

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host '[error] git is not available. Run bootstrap.ps1 first (it installs Git before setup).' -ForegroundColor Red
        exit 1
    }
    Write-Success 'git available'

    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        Write-Host '[warn] oh-my-posh not found — font install will be skipped. Run the Packages phase first.' -ForegroundColor Yellow
    } else {
        Write-Success 'oh-my-posh available'
    }
}

# ---------------------------------------------------------------------------
# Phase 0: Init submodules
# ---------------------------------------------------------------------------

function Invoke-Submodules {
    Write-Phase 'Phase 0: Init submodules'
    git -C $RepoRoot submodule update --init --recursive
    Write-Success 'Submodules up to date'
}

# ---------------------------------------------------------------------------
# Phase 2: Install packages
# ---------------------------------------------------------------------------

function Invoke-Packages {
    Write-Phase 'Phase 2: Install packages'

    $packagesFile = Join-Path $RepoRoot 'config/packages.json'

    Write-Host '[setup] Running winget import...'
    winget import --import-file $packagesFile --accept-source-agreements --accept-package-agreements --disable-interactivity
    Write-Success 'WinGet packages installed'

    # Refresh PATH so newly installed tools (e.g. oh-my-posh) are visible without reopening the terminal.
    $env:PATH = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')

    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Host '[setup] Installing Meslo Nerd Font...'
        oh-my-posh font install meslo

        # oh-my-posh copies font files but does not write registry entries, so
        # Windows falls back to the old Powerline variant after a terminal restart.
        # Enumerate the newly copied files and register them explicitly.
        $fontsDir = "$env:USERPROFILE\AppData\Local\Microsoft\Windows\Fonts"
        $regPath  = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        $shell    = New-Object -ComObject Shell.Application
        $folder   = $shell.Namespace($fontsDir)
        Get-ChildItem "$fontsDir\MesloLGM*NerdFont*.ttf" -ErrorAction SilentlyContinue | ForEach-Object {
            $item     = $folder.ParseName($_.Name)
            $fontName = $folder.GetDetailsOf($item, 21)
            if (-not $fontName) { $fontName = $folder.GetDetailsOf($item, 0) }
            if ($fontName) {
                Set-ItemProperty -Path $regPath -Name "$fontName (TrueType)" -Value $_.FullName -ErrorAction SilentlyContinue
            }
        }

        Write-Success 'Meslo Nerd Font installed'
    } else {
        Write-Skip 'oh-my-posh not available yet — re-run setup after winget completes and PATH refreshes'
    }
}

# ---------------------------------------------------------------------------
# Phase 3: Create symlinks
# ---------------------------------------------------------------------------

function Invoke-Symlinks {
    Write-Phase 'Phase 3: Create symlinks'

    # PowerShell profile stub — points $PROFILE to repo's profile.ps1
    $profileDir  = Split-Path $PROFILE.CurrentUserAllHosts
    $profileStub = $PROFILE.CurrentUserAllHosts
    $profileSrc  = Join-Path $RepoRoot 'powershell/profile.ps1'

    if (-not (Test-Path $profileSrc)) {
        Write-Skip "powershell/profile.ps1 not found in repo — skipping profile stub"
    } else {
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        if (Test-Path $profileStub) {
            $existing = Get-Item $profileStub
            if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $profileSrc) {
                Write-Skip 'PowerShell profile stub already set'
            } else {
                Rename-Item $profileStub "$profileStub.bak" -Force
                Write-Host '[setup] Existing profile backed up to profile.ps1.bak'
                New-Item -ItemType SymbolicLink -Path $profileStub -Target $profileSrc | Out-Null
                Write-Success 'PowerShell profile stub created'
            }
        } else {
            New-Item -ItemType SymbolicLink -Path $profileStub -Target $profileSrc | Out-Null
            Write-Success 'PowerShell profile stub created'
        }
    }

    # Neovim config — points $env:LOCALAPPDATA\nvim to submodule's nvim directory
    $nvimLink = "$env:LOCALAPPDATA\nvim"
    $nvimSrc  = Join-Path $RepoRoot 'submodules\dotfiles\nvim\.config\nvim'

    if (-not (Test-Path $nvimSrc)) {
        Write-Skip 'submodules/dotfiles/nvim not found — run submodule init first'
    } elseif (Test-Path $nvimLink) {
        $existing = Get-Item $nvimLink
        if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $nvimSrc) {
            Write-Skip 'Neovim config symlink already set'
        } else {
            Rename-Item $nvimLink "$nvimLink.bak" -Force
            Write-Host '[setup] Existing nvim config backed up to nvim.bak'
            New-Item -ItemType SymbolicLink -Path $nvimLink -Target $nvimSrc | Out-Null
            Write-Success 'Neovim config symlink created'
        }
    } else {
        New-Item -ItemType SymbolicLink -Path $nvimLink -Target $nvimSrc | Out-Null
        Write-Success 'Neovim config symlink created'
    }

    # Zellij config — points %APPDATA%\Zellij\config\config.kdl to submodule's config
    # Shared with WSL; SHELL env var controls which shell is used per platform
    $zellijConfigDir  = "$env:APPDATA\Zellij\config"
    $zellijConfigLink = "$zellijConfigDir\config.kdl"
    $zellijConfigSrc  = Join-Path $RepoRoot 'submodules\dotfiles\zellij\.config\zellij\config.kdl'

    if (-not (Test-Path $zellijConfigSrc)) {
        Write-Skip 'submodules/dotfiles/zellij config not found — run submodule init first'
    } else {
        if (-not (Test-Path $zellijConfigDir)) {
            New-Item -ItemType Directory -Path $zellijConfigDir -Force | Out-Null
        }

        if (Test-Path $zellijConfigLink) {
            $existing = Get-Item $zellijConfigLink -Force
            if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $zellijConfigSrc) {
                Write-Skip 'Zellij config symlink already set'
            } else {
                Rename-Item $zellijConfigLink "$zellijConfigLink.bak" -Force
                Write-Host '[setup] Existing zellij config backed up to config.kdl.bak'
                New-Item -ItemType SymbolicLink -Path $zellijConfigLink -Target $zellijConfigSrc | Out-Null
                Write-Success 'Zellij config symlink created'
            }
        } else {
            New-Item -ItemType SymbolicLink -Path $zellijConfigLink -Target $zellijConfigSrc | Out-Null
            Write-Success 'Zellij config symlink created'
        }
    }

    # Git config — points ~\.config\git to submodule's git config directory
    $gitLink = "$env:USERPROFILE\.config\git"
    $gitSrc  = Join-Path $RepoRoot 'submodules\dotfiles\git\.config\git'

    # Remove legacy ~/.gitconfig so dotfiles config is always the source of truth
    $legacyGitConfig = "$env:USERPROFILE\.gitconfig"
    if (Test-Path $legacyGitConfig) {
        Remove-Item $legacyGitConfig -Force
        Write-Host '[setup] Removed ~/.gitconfig — dotfiles config takes over'
    }

    if (-not (Test-Path $gitSrc)) {
        Write-Skip 'submodules/dotfiles/git not found — run submodule init first'
    } elseif (Test-Path $gitLink) {
        $existing = Get-Item $gitLink
        if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $gitSrc) {
            Write-Skip 'Git config symlink already set'
        } else {
            Rename-Item $gitLink "$gitLink.bak" -Force
            Write-Host '[setup] Existing git config backed up to git.bak'
            New-Item -ItemType SymbolicLink -Path $gitLink -Target $gitSrc | Out-Null
            Write-Success 'Git config symlink created'
        }
    } else {
        $gitLinkParent = Split-Path $gitLink
        if (-not (Test-Path $gitLinkParent)) {
            New-Item -ItemType Directory -Path $gitLinkParent -Force | Out-Null
        }
        New-Item -ItemType SymbolicLink -Path $gitLink -Target $gitSrc | Out-Null
        Write-Success 'Git config symlink created'
    }
}

# ---------------------------------------------------------------------------
# Phase 4: Shell config — install PS modules
# ---------------------------------------------------------------------------

function Invoke-Shell {
    Write-Phase 'Phase 4: Shell config'

    $modulesFile = Join-Path $RepoRoot 'powershell/modules.json'
    $cfg = Get-Content $modulesFile | ConvertFrom-Json

    foreach ($mod in $cfg.modules) {
        if (Get-Module -ListAvailable -Name $mod.name) {
            Write-Skip "$($mod.name) already installed"
        } else {
            Write-Host "[setup] Installing module $($mod.name)..."
            Install-Module -Name $mod.name -Scope $mod.scope -Force -SkipPublisherCheck
            Write-Success "$($mod.name) installed"
        }
    }

    # Set SHELL env var so zellij uses pwsh on Windows (WSL inherits its own $SHELL from the OS)
    $currentShell = [System.Environment]::GetEnvironmentVariable('SHELL', 'User')
    if ($currentShell -eq 'pwsh') {
        Write-Skip 'SHELL=pwsh already set'
    } else {
        [System.Environment]::SetEnvironmentVariable('SHELL', 'pwsh', 'User')
        $env:SHELL = 'pwsh'
        Write-Success 'SHELL=pwsh set in user environment'
    }
}

# ---------------------------------------------------------------------------
# Run phases
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   Windows 11 Dotfiles — Setup      ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

Invoke-ValidatePrerequisites

Invoke-Submodules

if ($All -or $Packages) { Invoke-Packages }
if ($All -or $Symlinks) { Invoke-Symlinks }
if ($All -or $Shell)    { Invoke-Shell    }

Write-Host ''
Write-Host '====================================' -ForegroundColor Cyan
Write-Host '   Setup complete!                  ' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan
Write-Host ''
