BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot
    function agency { throw 'Tests must not invoke the real Agency CLI' }
    function zoxide { throw 'Tests must not invoke the real zoxide binary' }
    function glazewm { throw 'Profile startup must not launch the window manager' }
    . (Join-Path $repoRoot 'powershell\aliases.ps1')
}

Describe 'Copilot routing' {
    It 'prefers Agency and forwards arguments without flattening them' {
        Mock Get-Command {
            [pscustomobject]@{ Source = { @('agency') + $args } }
        } -ParameterFilter { $Name -eq 'agency' -and $CommandType -eq 'Application' }
        (copilot '--prompt' 'hello world') -join '|' | Should -Be 'agency|copilot|--prompt|hello world'
    }

    It 'uses standalone Copilot when Agency is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'agency' }
        Mock Get-Command {
            [pscustomobject]@{ Source = { @('standalone') + $args } }
        } -ParameterFilter { $Name -eq 'copilot' -and $CommandType -eq 'Application' }
        (copilot '--prompt' 'hello world') -join '|' | Should -Be 'standalone|--prompt|hello world'
    }

    It 'surfaces a missing standalone executable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'agency' }
        Mock Get-Command { throw 'Copilot is not installed' } -ParameterFilter { $Name -eq 'copilot' }
        { copilot } | Should -Throw '*not installed*'
    }
}

Describe 'GlazeWM routing' {
    BeforeEach {
        $originalGlazewmConfigPath = $env:GLAZEWM_CONFIG_PATH
        $originalLastExitCode = $global:LASTEXITCODE
        $env:GLAZEWM_CONFIG_PATH = Join-Path $TestDrive 'dotfiles with spaces\glazewm\config.yaml'
        Mock Get-Command {
            [pscustomobject]@{ Source = { @('native') + $args } }
        } -ParameterFilter { $Name -eq 'glazewm' -and $CommandType -eq 'Application' }
    }

    AfterEach {
        $env:GLAZEWM_CONFIG_PATH = $originalGlazewmConfigPath
        $global:LASTEXITCODE = $originalLastExitCode
    }

    It 'passes the profile config explicitly for <Case> without depending on child environment inheritance' -ForEach @(
        @{ Case = 'start'; Arguments = @('start'); Expected = @('start') }
        @{ Case = 'bare invocation'; Arguments = @(); Expected = @('start') }
        @{ Case = 'verbose start'; Arguments = @('start', '--verbose'); Expected = @('start', '--verbose') }
    ) {
        $expectedArguments = @('native') + $Expected + @('--config', $env:GLAZEWM_CONFIG_PATH)
        (glazewm @Arguments) -join '|' | Should -Be ($expectedArguments -join '|')
        Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'glazewm' -and $CommandType -eq 'Application'
        }
    }

    It 'preserves an explicit config using <Case>' -ForEach @(
        @{ Case = 'long option'; Arguments = @('start', '--config', 'C:\custom config\config.yaml') }
        @{ Case = 'long equals option'; Arguments = @('start', '--config=C:\custom config\config.yaml') }
        @{ Case = 'short option'; Arguments = @('start', '-c', 'C:\custom config\config.yaml') }
        @{ Case = 'short attached value'; Arguments = @('start', '-cC:\custom config\config.yaml') }
        @{ Case = 'combined short options'; Arguments = @('start', '-vc', 'C:\custom config\config.yaml') }
    ) {
        $env:GLAZEWM_CONFIG_PATH = $null
        (glazewm @Arguments) -join '|' | Should -Be ((@('native') + $Arguments) -join '|')
    }

    It 'forwards <Case> unchanged without requiring a profile config' -ForEach @(
        @{ Case = 'queries'; Arguments = @('query', 'app-metadata') }
        @{ Case = 'reloads'; Arguments = @('command', 'wm-reload-config') }
        @{ Case = 'subscriptions'; Arguments = @('sub', '--events', 'user_config_changed') }
        @{ Case = 'help'; Arguments = @('--help') }
        @{ Case = 'start help'; Arguments = @('start', '--help') }
        @{ Case = 'short start help'; Arguments = @('start', '-h') }
    ) {
        $env:GLAZEWM_CONFIG_PATH = $null
        (glazewm @Arguments) -join '|' | Should -Be ((@('native') + $Arguments) -join '|')
    }

    It 'surfaces an unset profile config instead of falling back to the default file' {
        $env:GLAZEWM_CONFIG_PATH = $null
        { glazewm start } | Should -Throw '*GLAZEWM_CONFIG_PATH*'
    }

    It 'surfaces a missing executable' {
        Mock Get-Command { throw 'GlazeWM is not installed' } -ParameterFilter { $Name -eq 'glazewm' }
        { glazewm start } | Should -Throw '*not installed*'
    }

    It 'preserves the native exit status' {
        Mock Get-Command {
            [pscustomobject]@{ Source = { $global:LASTEXITCODE = 7 } }
        } -ParameterFilter { $Name -eq 'glazewm' }
        glazewm command wm-reload-config
        $LASTEXITCODE | Should -Be 7
    }
}

Describe 'Git shortcuts' {
    BeforeEach {
        $previousLastExitCode = $global:LASTEXITCODE
        Mock git {
            $global:LASTEXITCODE = 0
            'git|' + ($args -join '|')
        }
    }

    AfterEach {
        $global:LASTEXITCODE = $previousLastExitCode
    }

    It 'passes Git arguments as distinct values, including spaces and punctuation' {
        (ga 'file with spaces.txt') | Should -Be 'git|add|file with spaces.txt'
        (gca! --no-edit) | Should -Be 'git|commit|--verbose|--all|--amend|--no-edit'
        (gdup --stat) | Should -Be 'git|diff|@{upstream}|--stat'
        (gbdf topic) | Should -Be 'git|branch|--delete|--force|topic'
        (gcbf topic main) | Should -Be 'git|checkout|-B|topic|main'
    }

    It 'passes log formats containing spaces as one argument' {
        $format = '--pretty=%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset'
        (glol --max-count=3) | Should -Be "git|log|--graph|$format|--max-count=3"
        (glp oneline) | Should -Be 'git|log|--pretty=oneline'
        (glp oneline -2) | Should -Be 'git|log|--pretty=oneline|-2'
    }

    It 'preserves PowerShell built-ins instead of replacing their Git counterparts' {
        $builtins = @{
            gc = 'Get-Content'
            gcm = 'Get-Command'
            gcs = 'Get-PSCallStack'
            gl = 'Get-Location'
            gm = 'Get-Member'
            gp = 'Get-ItemProperty'
            gpv = 'Get-ItemPropertyValue'
        }
        foreach ($name in $builtins.Keys) {
            (Get-Alias $name).Definition | Should -Be $builtins[$name]
        }
    }

    It 'resolves a current branch without fetching or pushing' {
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'symbolic-ref') { return 'topic/test' }
            'git|' + ($args -join '|')
        }
        (ggpush) | Should -Be 'git|push|origin|topic/test'
        (ggp 'other-branch') | Should -Be 'git|push|origin|other-branch'
        (gpsup) | Should -Be 'git|push|--set-upstream|origin|topic/test'
    }

    It 'does not guess a branch when no default branch can be found' {
        Mock git {
            if ($args[0] -eq 'rev-parse') { $global:LASTEXITCODE = 0 }
            else { $global:LASTEXITCODE = 1 }
        }
        { gswm } | Should -Throw '*Cannot determine the main Git branch*'
    }

    It 'uses the remote HEAD when no conventional main branch exists' {
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'show-ref') { $global:LASTEXITCODE = 1 }
            elseif ($args[0] -eq 'symbolic-ref') { return 'origin/release' }
            elseif ($args[0] -eq 'switch') { return 'git|' + ($args -join '|') }
        }
        (gswm) | Should -Be 'git|switch|release'
    }

    It 'deletes only branches with gone upstreams, with and without force' {
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'for-each-ref') {
                "topic/deleted`t[gone]"
                "topic/active`t[ahead 1]"
            } else {
                'git|' + ($args -join '|')
            }
        }
        (gbgd) | Should -Be 'git|branch|-d|topic/deleted'
        (gbgdf) | Should -Be 'git|branch|-D|topic/deleted'
    }

    It 'does not push after a failed pull' {
        Mock git {
            if ($args[0] -eq 'push') { throw 'A failed pull must not be followed by a push.' }
            $global:LASTEXITCODE = 1
        }
        ggpnp 'topic/test'
        $LASTEXITCODE | Should -Be 1
    }
}

Describe 'Gone branch detection' {
    It 'recognizes a configured upstream whose remote branch no longer exists' {
        if (-not (Get-Command git -CommandType Application -ErrorAction Ignore)) {
            Set-ItResult -Skipped -Because 'Git is not installed'
            return
        }

        $repo = Join-Path $TestDrive 'gone-branch-repo'
        New-Item -ItemType Directory -Path $repo | Out-Null
        & git.exe -C $repo init --quiet --initial-branch=main
        & git.exe -C $repo -c user.name=AliasTest -c user.email=alias@example.invalid `
            -c commit.gpgsign=false commit --quiet --allow-empty -m initial
        & git.exe -C $repo branch topic
        & git.exe -C $repo remote add origin 'https://example.invalid/repo.git'
        & git.exe -C $repo config branch.topic.remote origin
        & git.exe -C $repo config branch.topic.merge refs/heads/topic
        Push-Location $repo
        try {
            @(Get-GitGoneBranches) | Should -Contain 'topic'
            (gbg) | Should -Match 'topic.*: gone\]'
        } finally {
            Pop-Location
        }
    }
}

Describe 'Profile startup' {
    BeforeEach {
        $originalLocalAppData = $env:LOCALAPPDATA
        $originalHerdrConfigPath = $env:HERDR_CONFIG_PATH
        $originalGlazewmConfigPath = $env:GLAZEWM_CONFIG_PATH
        $env:LOCALAPPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        $zoxide = Join-Path $env:LOCALAPPDATA 'fake-zoxide.ps1'
        Set-Content -LiteralPath $zoxide -Value @'
$global:ZoxideTestRuns++
$global:LASTEXITCODE = 0
'$global:ZoxideTestLoaded = $true'
'@
        $global:ZoxideTestRuns = 0
        $global:ZoxideTestLoaded = $false
        $mise = Join-Path $env:LOCALAPPDATA 'fake-mise.ps1'
        Set-Content -LiteralPath $mise -Value @'
if (($args -join '|') -ne 'activate|pwsh') { throw 'Unexpected mise arguments' }
$global:LASTEXITCODE = 0
'$global:MiseTestLoaded = $true'
'@
        $global:MiseTestLoaded = $false
        Set-Variable -Name HOME -Value $env:LOCALAPPDATA -Force
        Mock Get-Command { [pscustomobject]@{ Source = $zoxide } } -ParameterFilter { $Name -eq 'zoxide' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'mise' }
        Mock Get-Command { [pscustomobject]@{ Source = 'git.exe' } } -ParameterFilter { $Name -eq 'git' }
        Mock Import-Module {
            $global:GitPromptSettings = @{ EnableFileStatus = $true; EnableStashStatus = $true }
        } -ParameterFilter { $Name -eq 'posh-git' }
        Mock Install-Module { throw 'Profile startup must not install modules' }
        Mock Get-Command { throw 'Profile startup must not launch the window manager' } -ParameterFilter {
            $Name -eq 'glazewm' -and $CommandType -eq 'Application'
        }
        Mock Write-Warning {}
    }

    AfterEach {
        $env:LOCALAPPDATA = $originalLocalAppData
        $env:HERDR_CONFIG_PATH = $originalHerdrConfigPath
        $env:GLAZEWM_CONFIG_PATH = $originalGlazewmConfigPath
        Remove-Variable -Name ZoxideTestRuns,ZoxideTestLoaded,MiseTestLoaded -Scope Global -ErrorAction Ignore
        Remove-Variable -Name GitPromptSettings -Scope Global -ErrorAction Ignore
    }

    It 'loads repo-relative aliases and UTF-8 settings without optional tools' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'zoxide' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        (Get-Alias v).Definition | Should -Be 'nvim'
        (Get-Alias ll).Definition | Should -Be 'Get-ChildItem'
        (Get-Alias y).Definition | Should -Be 'yazi'
        (Get-Alias g).Definition | Should -Be 'git'
        (Get-Alias ga).Definition | Should -Be 'Invoke-GitShortcut'
        $env:PYTHONIOENCODING | Should -Be 'utf-8'
        $global:MiseTestLoaded | Should -BeFalse
        Should -Invoke Write-Warning -Times 0
    }

    It 'imports the pinned Git prompt globally without file or stash scans or downloads' {
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        Should -Invoke Import-Module -Times 1 -ParameterFilter {
            $Name -eq 'posh-git' -and $RequiredVersion -eq '1.1.0' -and $Global -and $ErrorAction -eq 'Stop'
        }
        $GitPromptSettings.EnableFileStatus | Should -BeFalse
        $GitPromptSettings.EnableStashStatus | Should -BeFalse
        Should -Invoke Install-Module -Times 0
        Should -Invoke Write-Warning -Times 0
    }

    It 'does not import posh-git when Git is missing' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        Should -Invoke Import-Module -Times 0 -ParameterFilter { $Name -eq 'posh-git' }
        Should -Invoke Write-Warning -Times 0
    }

    It 'warns about missing or broken modules without breaking aliases, mise, or zoxide' {
        Mock Import-Module { throw 'pinned module is missing' } -ParameterFilter { $Name -eq 'posh-git' }
        Mock Get-Command { [pscustomobject]@{ Source = $mise } } -ParameterFilter { $Name -eq 'mise' }
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        $global:MiseTestLoaded | Should -BeTrue
        $global:ZoxideTestLoaded | Should -BeTrue
        (Get-Alias v).Definition | Should -Be 'nvim'
        Should -Invoke Write-Warning -Times 1 -ParameterFilter {
            $Message -like '*Git prompt*pinned module is missing*setup.ps1 -PackagesOnly*'
        }
        Should -Invoke Install-Module -Times 0
    }

    It 'activates mise in the current PowerShell session when installed' {
        Mock Get-Command { [pscustomobject]@{ Source = $mise } } -ParameterFilter {
            $Name -eq 'mise' -and $CommandType -eq 'Application'
        }
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        $global:MiseTestLoaded | Should -BeTrue
        $global:ZoxideTestLoaded | Should -BeTrue
        Should -Invoke Write-Warning -Times 0
    }

    It 'warns about mise <Case> without breaking the remaining profile' -ForEach @(
        @{ Case = 'command failure'; Body = '$global:LASTEXITCODE = 7; ''$global:MiseTestLoaded = $true''' }
        @{ Case = 'empty output'; Body = '$global:LASTEXITCODE = 0' }
        @{ Case = 'invalid PowerShell'; Body = '$global:LASTEXITCODE = 0; ''if (''' }
        @{ Case = 'initializer failure'; Body = '$global:LASTEXITCODE = 0; ''throw "simulated initialization failure"''' }
    ) {
        Set-Content -LiteralPath $mise -Value $Body
        Mock Get-Command { [pscustomobject]@{ Source = $mise } } -ParameterFilter {
            $Name -eq 'mise' -and $CommandType -eq 'Application'
        }
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        $global:MiseTestLoaded | Should -BeFalse
        $global:ZoxideTestLoaded | Should -BeTrue
        (Get-Alias v).Definition | Should -Be 'nvim'
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*mise*' }
    }

    It 'uses this clone for <Tool> settings instead of an inherited obsolete config path' -ForEach @(
        @{ Tool = 'Herdr'; Variable = 'HERDR_CONFIG_PATH'; ConfigPath = 'herdr\config.toml' }
        @{ Tool = 'GlazeWM'; Variable = 'GLAZEWM_CONFIG_PATH'; ConfigPath = 'glazewm\config.yaml' }
    ) {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'zoxide' }
        [Environment]::SetEnvironmentVariable($Variable, (Join-Path $TestDrive 'old-clone\config'), 'Process')
        Push-Location $TestDrive
        try {
            . (Join-Path $repoRoot 'powershell\profile.ps1')
            $expected = Join-Path $repoRoot $ConfigPath
            [Environment]::GetEnvironmentVariable($Variable, 'Process') | Should -Be $expected
            Test-Path -LiteralPath $expected -PathType Leaf | Should -BeTrue
            . (Join-Path $repoRoot 'powershell\profile.ps1')
            [Environment]::GetEnvironmentVariable($Variable, 'Process') | Should -Be $expected
        } finally {
            Pop-Location
        }
        Should -Invoke Get-Command -Times 0 -ParameterFilter {
            $Name -eq 'glazewm' -and $CommandType -eq 'Application'
        }
        Should -Invoke Write-Warning -Times 0
    }

    It 'reuses a valid cache without spawning zoxide at each startup' {
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        $global:ZoxideTestRuns | Should -Be 1
        $global:ZoxideTestLoaded | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'WhereZenZoo\cache\zoxide-init.ps1') | Should -BeTrue
    }

    It 'regenerates the cache after the binary changes' {
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        Add-Content -LiteralPath $zoxide -Value '# changed binary'
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        $global:ZoxideTestRuns | Should -Be 2
    }

    It 'reports init failures without caching broken output or breaking the rest of the profile' {
        Set-Content -LiteralPath $zoxide -Value '$global:LASTEXITCODE = 1'
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        Should -Invoke Write-Warning -Times 1 -ParameterFilter { $Message -like '*zoxide*' }
        Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'WhereZenZoo\cache\zoxide-init.ps1') | Should -BeFalse
        (Get-Alias v).Definition | Should -Be 'nvim'
    }
}
