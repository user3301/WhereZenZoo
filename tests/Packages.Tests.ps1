BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
    function winget { throw 'Tests must not invoke the real WinGet executable' }
}

Describe 'WinGet package installation' {
    BeforeEach {
        $package = @{ id = 'Example.Tool'; command = 'example-tool.exe' }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'example-tool.exe' }
        Mock Update-SessionPath {}
    }

    It 'accepts an existing application but not an alias as an installed tool' {
        Mock Get-Command { [pscustomobject]@{ Source = 'example-tool.exe' } } -ParameterFilter {
            $Name -eq 'example-tool.exe' -and $CommandType -eq 'Application'
        }
        Mock winget { throw 'Must not call winget for an existing application' }
        Install-WinGetPackage $package
        Should -Invoke winget -Times 0
    }

    It 'skips packages that WinGet already knows about' {
        Mock winget { $global:LASTEXITCODE = 0 }
        Install-WinGetPackage $package
        Should -Invoke winget -Times 1
    }

    It 'installs only after the specific no-applications-found result' {
        Mock winget {
            if ($args[0] -eq 'list') { $global:LASTEXITCODE = -1978335212 }
            else { $global:LASTEXITCODE = 0 }
        }
        Install-WinGetPackage $package
        Should -Invoke winget -Times 2
        Should -Invoke Update-SessionPath -Times 1
    }

    It 'surfaces source and network errors instead of treating them as missing packages' {
        Mock winget { $global:LASTEXITCODE = -1978335221; 'source unavailable' }
        { Install-WinGetPackage $package } | Should -Throw '*source unavailable*'
        Should -Invoke winget -Times 1
    }

    It 'propagates installer failures rather than reporting success' {
        Mock winget {
            if ($args[0] -eq 'list') { $global:LASTEXITCODE = -1978335212 }
            else { $global:LASTEXITCODE = 5 }
        }
        { Install-WinGetPackage $package } | Should -Throw '*exit 5*'
    }

    It 'reports reboot-required installs explicitly' {
        Mock winget {
            if ($args[0] -eq 'list') { $global:LASTEXITCODE = -1978335212 }
            else { $global:LASTEXITCODE = -1978334967 }
        }
        { Install-WinGetPackage $package } | Should -Throw '*restart Windows*'
    }

    It 'does not reinstall an already usable C++ toolchain' {
        Mock Test-CppBuildTools { $true }
        Mock winget { throw 'An existing C++ workload must not be reinstalled' }
        Install-WinGetPackage @{ id = 'Microsoft.VisualStudio.2022.BuildTools' }
        Should -Invoke winget -Times 0
    }

    It 'adds the C++ workload even when an incomplete Build Tools shell was already installed' {
        $script:cppReady = $false
        Mock Test-CppBuildTools { $script:cppReady }
        Mock winget {
            $script:cppReady = $true
            $global:LASTEXITCODE = 0
        }
        Install-WinGetPackage @{
            id = 'Microsoft.VisualStudio.2022.BuildTools'
            override = '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        }
        Should -Invoke winget -Times 1 -ParameterFilter {
            $args[0] -eq 'install' -and $args -contains '--force' -and $args -contains '--override'
        }
        Should -Invoke Test-CppBuildTools -Times 2
    }

    It 'keeps Build Tools optional and has no Make dependency' {
        $packages = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\config\packages.json') -Raw |
            ConvertFrom-Json -AsHashtable
        @($packages | Where-Object { -not $_.optional }).Count | Should -Be 8
        @($packages | Where-Object { $_.optional }).Count | Should -Be 1
        ($packages | Where-Object { $_.optional }).id | Should -Be 'Microsoft.VisualStudio.2022.BuildTools'
        $packages.id | Should -Not -Contain 'ezwinports.make'
    }

}
