BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot
    function agency { throw 'Tests must not invoke the real Agency CLI' }
    function zoxide { throw 'Tests must not invoke the real zoxide binary' }
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

Describe 'Profile startup' {
    BeforeEach {
        $originalLocalAppData = $env:LOCALAPPDATA
        $originalHerdrConfigPath = $env:HERDR_CONFIG_PATH
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
        Mock Write-Warning {}
    }

    AfterEach {
        $env:LOCALAPPDATA = $originalLocalAppData
        $env:HERDR_CONFIG_PATH = $originalHerdrConfigPath
        Remove-Variable -Name ZoxideTestRuns,ZoxideTestLoaded,MiseTestLoaded -Scope Global -ErrorAction Ignore
    }

    It 'loads repo-relative aliases and UTF-8 settings without optional tools' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'zoxide' }
        . (Join-Path $repoRoot 'powershell\profile.ps1')
        (Get-Alias v).Definition | Should -Be 'nvim'
        (Get-Alias ll).Definition | Should -Be 'Get-ChildItem'
        $env:PYTHONIOENCODING | Should -Be 'utf-8'
        $global:MiseTestLoaded | Should -BeFalse
        Should -Invoke Write-Warning -Times 0
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

    It 'uses this clone for Herdr settings instead of an inherited obsolete config path' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'zoxide' }
        $env:HERDR_CONFIG_PATH = Join-Path $TestDrive 'old-submodule\config.toml'
        Push-Location $TestDrive
        try {
            . (Join-Path $repoRoot 'powershell\profile.ps1')
            $env:HERDR_CONFIG_PATH | Should -Be (Join-Path $repoRoot 'herdr\config.toml')
        } finally {
            Pop-Location
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
