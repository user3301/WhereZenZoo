#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$BuildTools
)

# A child scope keeps preferences and helper variables out of an `irm ... | iex` caller.
& {
    [CmdletBinding()]
    param(
        [string]$Destination = (Join-Path $env:USERPROFILE 'dotfiles'),
        [switch]$BuildTools
    )

    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    if ($PSVersionTable.PSVersion.Major -lt 7 -or -not $IsWindows -or
        [Environment]::OSVersion.Version.Build -lt 22000) {
        throw 'Run this installer in PowerShell 7 on Windows 11.'
    }
    if (-not (Get-Command winget -CommandType Application -ErrorAction Ignore)) {
        throw 'WinGet is required. Install App Installer from the Microsoft Store, then rerun.'
    }
    if (-not (Get-Command git -CommandType Application -ErrorAction Ignore)) {
        & winget install --id Git.Git --exact --source winget --silent `
            --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Installing Git failed (winget exit $LASTEXITCODE)." }
        $paths = @(
            $env:PATH
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            [Environment]::GetEnvironmentVariable('Path', 'User')
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
        )
        $env:PATH = (($paths -join ';').Split(';', [StringSplitOptions]::RemoveEmptyEntries) |
            Select-Object -Unique) -join ';'
        if (-not (Get-Command git -CommandType Application -ErrorAction Ignore)) {
            throw 'Git is installed but not on PATH. Open a new PowerShell 7 terminal and rerun.'
        }
    }

    $repo = 'https://github.com/user3301/WhereZenZoo.git'
    $Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
    if (Get-Item -LiteralPath $Destination -Force -ErrorAction Ignore) {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination '.git'))) {
            throw "'$Destination' already exists and is not a clone. Move it aside or choose -Destination."
        }
        $origin = & git -C $Destination remote get-url origin
        if ($LASTEXITCODE -ne 0 -or $origin -notin @(
                $repo, ($repo -replace '\.git$', ''), 'git@github.com:user3301/WhereZenZoo.git'
            )) {
            throw "'$Destination' is not a WhereZenZoo clone. No files were changed."
        }
        $branch = & git -C $Destination branch --show-current
        if ($LASTEXITCODE -ne 0 -or $branch -ne 'main') {
            throw "The clone must be on main for remote updates. Run its setup.ps1 directly to use another branch."
        }
        $status = & git -C $Destination status --porcelain
        if ($LASTEXITCODE -ne 0) { throw "Cannot inspect '$Destination' (git exit $LASTEXITCODE)." }
        if ($status) {
            throw "The clone has uncommitted changes. Commit/stash them before updating, or run its setup.ps1 directly."
        }
        & git -C $Destination pull --ff-only origin main | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Updating the clone failed (git exit $LASTEXITCODE)." }
    } else {
        & git clone --branch main --single-branch $repo $Destination | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Cloning failed (git exit $LASTEXITCODE)." }
    }

    $setup = Join-Path $Destination 'setup.ps1'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Setup script missing: $setup" }
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setup)
    if ($BuildTools) { $arguments += '-BuildTools' }
    & (Join-Path $PSHOME 'pwsh.exe') @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Setup failed (exit $LASTEXITCODE). Fix the reported error and rerun; your terminal remains open."
    }
} @PSBoundParameters
