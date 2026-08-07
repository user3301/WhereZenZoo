#Requires -Version 5.1
<#
.SYNOPSIS
    Main WhereZenZoo setup orchestrator (winget-based).
.DESCRIPTION
    Installs the winget packages declared in config/packages.json and creates the
    dotfile symlinks (Neovim config from the dotfiles submodule, PowerShell
    directory and PowerShell 7 profile, and Git config).

    The run is idempotent: packages that are already installed are skipped, and
    symlinks that already point at the right target are left alone. Packages this
    script installs are recorded in a per-user state file so uninstall.ps1 can
    revert only what was actually installed here.
.PARAMETER All
    Runs every phase. This is the default when no phase flag is supplied.
.PARAMETER Packages
    Installs the winget packages listed in config/packages.json.
.PARAMETER Symlinks
    Creates the Neovim, PowerShell, and Git configuration symlinks.
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
# winget/git return non-zero for benign cases (reboot required, no applicable
# upgrade, etc.). Don't let PowerShell 7.4+ turn those into terminating errors -
# we inspect $LASTEXITCODE and verify results ourselves.
$PSNativeCommandUseErrorActionPreference = $false
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
    'ajeetdsouza.zoxide'      = 'zoxide'
    'GitHub.cli'              = 'gh'
    'GitHub.Copilot'          = 'copilot'
}

# Per-package winget install overrides. Some packages need extra installer args
# that the generic --silent install can't express. Build Tools must be told to
# add the C++ (VCTools) workload + a Windows SDK, otherwise only the installer
# shell is placed and nvim-treesitter still can't find cl.exe.
$InstallOverrides = @{
    'Microsoft.VisualStudio.2022.BuildTools' =
        '--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
}

# Packages that genuinely failed to install this run. The setup keeps going so a
# single bad package doesn't skip later phases, but a non-empty list makes the
# script exit non-zero so the failure is visible and you can fix it and re-run.
$script:PackageFailures = @()

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

    $Id = $Id.Trim()
    $path = Get-StatePath
    $dir  = Split-Path $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $ids = @()
    if (Test-Path $path) {
        try { $ids = @(Get-Content $path -Raw | ConvertFrom-Json | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Unique) } catch { $ids = @() }
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
        $wingetArgs = @(
            'install', '--id', $id, '--exact', '--source', 'winget',
            '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
        )
        if ($InstallOverrides.ContainsKey($id)) {
            $wingetArgs += @('--override', $InstallOverrides[$id])
        } else {
            $wingetArgs += '--silent'
        }
        winget @wingetArgs
        $code = $LASTEXITCODE
        Update-SessionPath

        # winget's exit code is unreliable (non-zero for reboot-required, etc.),
        # so confirm by presence instead. A single bad package must never abort
        # the run - the symlink phase still needs to happen.
        if (Test-PackageInstalled -Id $id) {
            Add-InstalledPackage -Id $id
            Write-Success "$id installed"
        } else {
            Write-Warn "$id did not install cleanly (winget exit $code); continuing"
            $script:PackageFailures += $id
        }
    }

    Update-SessionPath

    if ($script:PackageFailures) {
        Write-Warn ("May need a manual install: {0}" -f ($script:PackageFailures -join ', '))
    }
}

function New-SymbolicLinkCompat {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    # Windows PowerShell 5.1's New-Item -SymbolicLink omits the unprivileged-create
    # flag, so it demands admin even when Developer Mode is on. PowerShell 7 honors
    # Developer Mode. When running under 5.1 (e.g. via the Makefile / bootstrap),
    # delegate creation to pwsh so no elevation is needed.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($pwsh) {
            $escapedLink = $LinkPath.Replace("'", "''")
            $escapedTarget = $TargetPath.Replace("'", "''")
            & $pwsh.Source -NoProfile -Command "`$ErrorActionPreference = 'Stop'; New-Item -ItemType SymbolicLink -Path '$escapedLink' -Target '$escapedTarget' | Out-Null"
            if ($LASTEXITCODE -ne 0 -or -not (Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue)) {
                throw "Could not create the symlink at $LinkPath via pwsh."
            }
            return
        }
        Write-Warn 'pwsh not found; falling back to Windows PowerShell, which needs admin for symlinks.'
    }

    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
}

function Set-Symlink {
    param(
        [Parameter(Mandatory)][string]$LinkPath,
        [Parameter(Mandatory)][string]$TargetPath,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path $TargetPath)) {
        Write-Skip "$Description source missing ($TargetPath) - did the submodule init?"
        return
    }

    $parent = Split-Path $LinkPath
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $existing = Get-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.LinkType -eq 'SymbolicLink') {
            $rawTarget = $existing.Target | Select-Object -First 1
            $existingTarget = if ([System.IO.Path]::IsPathRooted($rawTarget)) {
                [System.IO.Path]::GetFullPath($rawTarget)
            } else {
                [System.IO.Path]::GetFullPath((Join-Path $existing.DirectoryName $rawTarget))
            }
            $desiredTarget = [System.IO.Path]::GetFullPath($TargetPath)

            if ([string]::Equals(
                $existingTarget.TrimEnd('\', '/'),
                $desiredTarget.TrimEnd('\', '/'),
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                Write-Skip "$Description already linked"
                return
            }

            # Repair only reparse points we created or can safely replace. Never use
            # Remove-Item -Recurse here: Windows PowerShell 5.1 can follow a directory
            # symlink and delete the target contents.
            if ($existing -is [System.IO.DirectoryInfo]) {
                [System.IO.Directory]::Delete($existing.FullName, $false)
            } else {
                [System.IO.File]::Delete($existing.FullName)
            }
            Write-Host "[setup] Replacing $Description symlink (was $rawTarget)"
        } else {
            throw "Cannot create $Description symlink at '$LinkPath': a real file or directory already exists. Move it aside manually and re-run setup."
        }
    }

    New-SymbolicLinkCompat -LinkPath $LinkPath -TargetPath $TargetPath
    Write-Success "$Description linked"
}

function Get-PowerShell7ProfilePath {
    # Query pwsh itself instead of constructing Documents\PowerShell manually.
    # This honors Known Folder redirection, including OneDrive KFR.
    Update-SessionPath

    if ($PSVersionTable.PSEdition -eq 'Core') {
        return $PROFILE.CurrentUserCurrentHost
    }

    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwsh) {
        throw 'PowerShell 7 is required to resolve and link its CurrentUserCurrentHost profile.'
    }

    $path = & $pwsh.Source -NoProfile -Command '$PROFILE.CurrentUserCurrentHost' 2>$null
    if (-not $path) {
        throw 'PowerShell 7 did not return its CurrentUserCurrentHost profile path.'
    }

    return ($path | Select-Object -First 1).Trim()
}

function Invoke-Symlinks {
    Write-Phase 'Create symlinks'

    # Refresh PATH so a freshly installed pwsh is discoverable for symlink creation
    # (see New-SymbolicLinkCompat) even when this phase runs on its own.
    Update-SessionPath

    # Make sure the dotfiles submodule (which holds the Neovim config) is present.
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git -C $RepoRoot submodule update --init --recursive | Out-Null
    }

    $nvimSrc = Join-Path $RepoRoot 'submodules\dotfiles\nvim\.config\nvim'
    Set-Symlink -LinkPath (Join-Path $env:LOCALAPPDATA 'nvim') -TargetPath $nvimSrc -Description 'Neovim config'

    # Keep profile contents at a stable home-relative path regardless of where the
    # repository was cloned. The profile link then targets this directory link.
    $repoPowerShell = Join-Path $RepoRoot 'powershell'
    $homePowerShell = Join-Path $HOME 'powershell'
    Set-Symlink -LinkPath $homePowerShell -TargetPath $repoPowerShell -Description 'PowerShell directory'

    $profilePath = Get-PowerShell7ProfilePath
    $profileSrc = Join-Path $homePowerShell 'profile.ps1'
    Set-Symlink -LinkPath $profilePath -TargetPath $profileSrc -Description 'PowerShell 7 CurrentUserCurrentHost profile'

    # Git reads ~/.config/git/config on all platforms (no XDG_CONFIG_HOME needed),
    # so linking the whole directory keeps identity/aliases/ignore rules identical
    # across every machine this setup runs on.
    $gitConfigSrc = Join-Path $RepoRoot 'submodules\dotfiles\git\.config\git'
    Set-Symlink -LinkPath (Join-Path $env:USERPROFILE '.config\git') -TargetPath $gitConfigSrc -Description 'Git config'
}

# Log the whole run to a file so failures are diagnosable even if the window closes.
$logDir = Join-Path $env:LOCALAPPDATA 'WhereZenZoo'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
$transcribing = $false
try { Start-Transcript -Path $logFile -Force | Out-Null; $transcribing = $true }
catch { Write-Warn "Could not start logging ($_); continuing without a log file." }

try {
    Write-Host ''
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host '   WhereZenZoo - Setup (winget)     ' -ForegroundColor Cyan
    Write-Host '====================================' -ForegroundColor Cyan

    Invoke-ValidatePrerequisites
    if ($All -or $Packages) { Invoke-Packages }
    if ($All -or $Symlinks) { Invoke-Symlinks }

    if ($script:PackageFailures.Count -gt 0) {
        Write-Host "`nSetup finished with errors - these packages did not install: $($script:PackageFailures -join ', ')." -ForegroundColor Red
        Write-Host 'Fix the cause and re-run; setup is idempotent and will skip what already succeeded.' -ForegroundColor Red
    } else {
        Write-Host "`nSetup complete. Restart your terminal to load persistent PATH changes." -ForegroundColor Green
    }
} finally {
    if ($transcribing) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host "Log saved to $logFile"
    }
}

# Exit non-zero on a real failure so it's visible to callers (make, wrappers).
if ($script:PackageFailures.Count -gt 0) { exit 1 }
