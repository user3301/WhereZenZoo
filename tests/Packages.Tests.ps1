BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
    function winget { throw 'Tests must not invoke the real WinGet executable' }
}

Describe 'PowerShell module installation' {
    BeforeEach {
        $script:moduleReady = $false
        Mock Get-Module {
            if ($script:moduleReady) { [pscustomobject]@{ Name = 'posh-git'; Version = [version]'1.1.0' } }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'posh-git' }
        Mock Install-Module { $script:moduleReady = $true }
    }

    It 'pins posh-git in the shared setup and profile manifest' {
        $modules = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\config\powershell-modules.json') -Raw |
            ConvertFrom-Json -AsHashtable)
        $modules.Count | Should -Be 1
        $modules[0].name | Should -Be 'posh-git'
        $modules[0].requiredVersion | Should -Be '1.1.0'
    }

    It 'skips the exact installed version without contacting the gallery' {
        $script:moduleReady = $true
        Install-PowerShellModule -Name posh-git -RequiredVersion 1.1.0
        Should -Invoke Install-Module -Times 0
    }

    It 'installs the pinned version for the current user even if another version exists' {
        Mock Get-Module {
            [pscustomobject]@{ Name = 'posh-git'; Version = [version]'1.0.0' }
            if ($script:moduleReady) { [pscustomobject]@{ Name = 'posh-git'; Version = [version]'1.1.0' } }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'posh-git' }
        Install-PowerShellModule -Name posh-git -RequiredVersion 1.1.0
        Should -Invoke Install-Module -Times 1 -ParameterFilter {
            $Name -eq 'posh-git' -and $RequiredVersion -eq [version]'1.1.0' -and
            $Scope -eq 'CurrentUser' -and $Repository -eq 'PSGallery' -and $Force -and $ErrorAction -eq 'Stop'
        }
    }

    It 'propagates gallery and installation failures' {
        Mock Install-Module { throw 'gallery unavailable' }
        { Install-PowerShellModule -Name posh-git -RequiredVersion 1.1.0 } |
            Should -Throw '*gallery unavailable*'
    }

    It 'does not report success when the installed module cannot be discovered' {
        Mock Install-Module {}
        { Install-PowerShellModule -Name posh-git -RequiredVersion 1.1.0 } |
            Should -Throw '*not discoverable*'
    }
}

Describe 'Package-only setup' {
    BeforeEach {
        $script:moduleReady = $false
        Mock Get-Command { [pscustomobject]@{ Source = 'winget.exe' } } -ParameterFilter {
            $Name -eq 'winget' -and $CommandType -eq 'Application'
        }
        Mock Get-Command { $null } -ParameterFilter {
            $CommandType -eq 'Application' -and $Name -ne 'winget'
        }
        Mock winget { $global:LASTEXITCODE = 0 }
        Mock Get-Module {
            if ($script:moduleReady) { [pscustomobject]@{ Name = 'posh-git'; Version = [version]'1.1.0' } }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'posh-git' }
        Mock Install-Module { $script:moduleReady = $true }
        Mock Get-ExecutionPolicy { throw 'Package-only setup must not check profile policy' }
        Mock New-Item { throw 'Package-only setup must not link configs' }
    }

    It 'installs the manifest module once across repeat runs without touching configs' {
        & (Join-Path $PSScriptRoot '..\setup.ps1') -PackagesOnly
        & (Join-Path $PSScriptRoot '..\setup.ps1') -PackagesOnly
        Should -Invoke Install-Module -Times 1 -ParameterFilter {
            $Name -eq 'posh-git' -and $RequiredVersion -eq [version]'1.1.0'
        }
        Should -Invoke Get-ExecutionPolicy -Times 0
        Should -Invoke New-Item -Times 0
    }

    It 'stops setup if module installation fails' {
        Mock Install-Module { throw 'gallery unavailable' }
        { & (Join-Path $PSScriptRoot '..\setup.ps1') -PackagesOnly } |
            Should -Throw '*gallery unavailable*'
    }
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

    It 'does not reinstall GlazeWM when its executable is already available' {
        $packages = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\config\packages.json') -Raw |
            ConvertFrom-Json -AsHashtable
        $glazewm = @($packages | Where-Object id -EQ 'glzr-io.glazewm')
        $glazewm.Count | Should -Be 1
        Mock Get-Command { [pscustomobject]@{ Source = 'glazewm.exe' } } -ParameterFilter {
            $Name -eq 'glazewm' -and $CommandType -eq 'Application'
        }
        Mock winget { throw 'An existing GlazeWM installation must not be reinstalled' }
        Install-WinGetPackage $glazewm[0]
        Should -Invoke winget -Times 0
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

    It 'installs mise, fzf, and GlazeWM by default while keeping Build Tools optional and avoiding Make' {
        $packages = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\config\packages.json') -Raw |
            ConvertFrom-Json -AsHashtable
        @($packages | Where-Object { -not $_.optional }).Count | Should -Be 11
        ($packages | Where-Object { $_.id -eq 'jdx.mise' -and -not $_.optional }).command |
            Should -Be 'mise'
        ($packages | Where-Object { $_.id -eq 'junegunn.fzf' -and -not $_.optional }).command |
            Should -Be 'fzf'
        ($packages | Where-Object { $_.id -eq 'glzr-io.glazewm' -and -not $_.optional }).command |
            Should -Be 'glazewm'
        @($packages | Where-Object { $_.optional }).Count | Should -Be 1
        ($packages | Where-Object { $_.optional }).id | Should -Be 'Microsoft.VisualStudio.2022.BuildTools'
        $packages.id | Should -Not -Contain 'ezwinports.make'
    }

}
