#Requires -Version 7.0

function Assert-Windows11 {
    if (-not $IsWindows -or [Environment]::OSVersion.Version.Build -lt 22000) {
        throw 'WhereZenZoo requires Windows 11 and PowerShell 7.'
    }
}

function Assert-ProfileExecutionPolicy {
    # setup may run with a process-only Bypass; the next terminal will not.
    foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
        $policy = Get-ExecutionPolicy -Scope $scope
        if ($policy -ne 'Undefined') { break }
    }
    if ($policy -in @('Undefined', 'Restricted', 'AllSigned')) {
        throw "Persistent execution policy '$policy' blocks the unsigned profile. If permitted, run Set-ExecutionPolicy -Scope CurrentUser RemoteSigned; otherwise follow your organization's signing policy."
    }
}

function Update-SessionPath {
    $paths = @(
        $env:PATH
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::GetEnvironmentVariable('Path', 'User')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    )
    $env:PATH = (($paths -join ';').Split(';', [StringSplitOptions]::RemoveEmptyEntries) |
        Select-Object -Unique) -join ';'
}

function Test-CppBuildTools {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    $installation = & $vswhere -latest -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0) { throw "vswhere failed (exit $LASTEXITCODE)." }
    return -not [string]::IsNullOrWhiteSpace(($installation -join ''))
}

function Install-WinGetPackage {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Package)

    $PSNativeCommandUseErrorActionPreference = $false
    $id = $Package.id
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'Every package must have an id.' }
    $cpp = $id -eq 'Microsoft.VisualStudio.2022.BuildTools'

    if (($cpp -and (Test-CppBuildTools)) -or
        ($Package.command -and (Get-Command $Package.command -CommandType Application -ErrorAction Ignore))) {
        Write-Host "[skip] $id is available"
        return
    }

    if (-not $cpp) {
        $result = & winget list --id $id --exact --source winget --accept-source-agreements --disable-interactivity
        $code = $LASTEXITCODE
        if ($code -eq 0) {
            Write-Host "[skip] $id is installed"
            return
        }
        # APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND; other failures are not absence.
        if ($code -ne -1978335212) {
            throw "Cannot query $id (winget exit $code): $($result -join [Environment]::NewLine)"
        }
    }

    $arguments = @(
        'install', '--id', $id, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    if ($cpp) {
        $arguments += @('--force', '--override', $Package.override)
    } else {
        $arguments += '--silent'
    }
    Write-Host "[install] $id"
    & winget @arguments | Out-Host
    $code = $LASTEXITCODE
    if ($code -in @(3010, -1978334967, -1978334966)) {
        throw "$id requires a reboot; restart Windows, then rerun setup."
    }
    if ($code -ne 0) { throw "Installing $id failed (winget exit $code)." }
    Update-SessionPath
    if ($cpp -and -not (Test-CppBuildTools)) {
        throw 'Build Tools was installed, but the C++ workload is missing. Rerun setup with -BuildTools.'
    }
}

function Get-Dotfiles {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$HomePath,
        [Parameter(Mandatory)][string]$LocalAppData,
        [Parameter(Mandatory)][string]$ProfilePath
    )

    @(
        @{ Kind = 'Junction'; Path = Join-Path $LocalAppData 'nvim'; Target = Join-Path $RepoRoot 'nvim' }
        @{ Kind = 'Junction'; Path = Join-Path $HomePath '.config\git'; Target = Join-Path $RepoRoot 'git' }
        @{ Kind = 'Profile'; Path = $ProfilePath; Target = Join-Path $RepoRoot 'powershell\profile.ps1' }
    )
}

function Copy-GitLocalConfig {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [switch]$CheckOnly
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return }
    if (Test-Path -LiteralPath $Target) {
        if ((Get-FileHash -LiteralPath $Source).Hash -ne (Get-FileHash -LiteralPath $Target).Hash) {
            throw "Two different Git config.local files exist. Merge '$Source' and '$Target' before rerunning."
        }
    } elseif (-not $CheckOnly) {
        Copy-Item -LiteralPath $Source -Destination $Target
        Write-Host '[preserved] Machine-local Git config (ignored by this repository)'
    }
}

function Get-ProfileLoader {
    param(
        [Parameter(Mandatory)][string]$Target,
        [switch]$Previous
    )
    $header = if ($Previous) {
        '# Previous profile link, preserved by WhereZenZoo.'
    } else {
        '# Managed by WhereZenZoo. Use uninstall.ps1 to restore the previous profile.'
    }
    "$header`r`n. '$($Target.Replace("'", "''"))'`r`n"
}

function Get-LinkTarget {
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item)
    $target = @($Item.Target)[0]
    if (-not [IO.Path]::IsPathRooted($target)) {
        $target = Join-Path (Split-Path $Item.FullName) $target
    }
    [IO.Path]::GetFullPath($target).TrimEnd('\')
}

function Test-Dotfile {
    param([Parameter(Mandatory)][hashtable]$Config)

    $item = Get-Item -LiteralPath $Config.Path -Force -ErrorAction Ignore
    if (-not $item) { return $false }
    if ($Config.Kind -eq 'Junction') {
        return $item.LinkType -eq 'Junction' -and
            (Get-LinkTarget $item) -eq [IO.Path]::GetFullPath($Config.Target).TrimEnd('\')
    }
    return $item -is [IO.FileInfo] -and -not $item.LinkType -and
        [IO.File]::ReadAllText($Config.Path) -ceq (Get-ProfileLoader $Config.Target)
}

function Assert-DotfileCanInstall {
    param([Parameter(Mandatory)][hashtable]$Config)

    $sourceType = if ($Config.Kind -eq 'Junction') { 'Container' } else { 'Leaf' }
    if (-not (Test-Path -LiteralPath $Config.Target -PathType $sourceType)) {
        throw "Config source is missing: $($Config.Target)"
    }
    $item = Get-Item -LiteralPath $Config.Path -Force -ErrorAction Ignore
    $backup = Get-Item -LiteralPath "$($Config.Path).wherezenzoo-backup" -Force -ErrorAction Ignore
    if ($item -and $backup -and -not (Test-Dotfile $Config)) {
        throw "Config changed and a backup already exists: $($backup.FullName). Move the changed config aside before rerunning."
    }
}

function Remove-ConfigLink {
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item)
    if ($Item.LinkType -notin @('Junction', 'SymbolicLink')) {
        throw "Refusing to remove a non-link: $($Item.FullName)"
    }
    if ($Item -is [IO.DirectoryInfo]) {
        [IO.Directory]::Delete($Item.FullName, $false)
    } else {
        [IO.File]::Delete($Item.FullName)
    }
}

function Install-Dotfile {
    param([Parameter(Mandatory)][hashtable]$Config)

    Assert-DotfileCanInstall $Config
    if (Test-Dotfile $Config) {
        Write-Host "[skip] $($Config.Path)"
        return
    }

    $path = $Config.Path
    $backup = "$path.wherezenzoo-backup"
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Ignore
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    if ($item) {
        if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
            $source = $item
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            while ($source.LinkType -in @('Junction', 'SymbolicLink')) {
                if (-not $seen.Add($source.FullName)) { throw "Circular config link: $path" }
                $target = Get-LinkTarget $source
                try {
                    $source = Get-Item -LiteralPath $target -Force -ErrorAction Stop
                } catch [System.Management.Automation.ItemNotFoundException] {
                    Write-Warning "Config link '$path' has a missing target '$target'. Preserving the broken link as '$backup'; rollback will restore the broken link, not its missing contents."
                    $source = $null
                    break
                }
            }
            if (-not $source) {
                Move-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
            } elseif ($Config.Kind -eq 'Profile') {
                # Preserve the script's own PSScriptRoot when restoring an old profile link.
                [IO.File]::WriteAllText($backup, (Get-ProfileLoader $source.FullName -Previous))
                Remove-ConfigLink $item
            } else {
                # A directory backup must survive removal of its old source.
                Copy-Item -LiteralPath $source.FullName -Destination $backup -Recurse -Force
                Remove-ConfigLink $item
            }
        } else {
            Move-Item -LiteralPath $path -Destination $backup
        }
        Write-Host "[backup] $backup"
    }

    try {
        if ($Config.Kind -eq 'Junction') {
            New-Item -ItemType Junction -Path $path -Target $Config.Target -ErrorAction Stop | Out-Null
        } else {
            [IO.File]::WriteAllText($path, (Get-ProfileLoader $Config.Target))
        }
    } catch {
        if (-not (Get-Item -LiteralPath $path -Force -ErrorAction Ignore) -and
            (Get-Item -LiteralPath $backup -Force -ErrorAction Ignore)) {
            Move-Item -LiteralPath $backup -Destination $path -ErrorAction Stop
        }
        throw
    }
    Write-Host "[linked] $path"
}

function Assert-DotfileCanRemove {
    param([Parameter(Mandatory)][hashtable]$Config)
    if ((Get-Item -LiteralPath $Config.Path -Force -ErrorAction Ignore) -and -not (Test-Dotfile $Config)) {
        throw "Config changed or is not managed by this clone; leaving it untouched: $($Config.Path)"
    }
}

function Remove-Dotfile {
    param([Parameter(Mandatory)][hashtable]$Config)

    Assert-DotfileCanRemove $Config
    $path = $Config.Path
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Ignore
    if ($item) {
        if ($Config.Kind -eq 'Junction') {
            Remove-ConfigLink $item
        } else {
            [IO.File]::Delete($path)
        }
        Write-Host "[removed] $path"
    }
    $backup = "$path.wherezenzoo-backup"
    if (Get-Item -LiteralPath $backup -Force -ErrorAction Ignore) {
        Move-Item -LiteralPath $backup -Destination $path
        Write-Host "[restored] $path"
    }
}
