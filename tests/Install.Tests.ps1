BeforeAll {
    $installer = Join-Path $PSScriptRoot '..\install.ps1'
    function git { throw 'Tests must not invoke Git or access the network' }
    function winget { throw 'Tests must not install applications' }
    function New-TestClone {
        param([string]$Path)
        New-Item -ItemType Directory -Path (Join-Path $Path '.git') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'setup.ps1') -Value @'
param([switch]$BuildTools)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-ran.txt') -Value "BuildTools=$BuildTools"
'@
    }
}

Describe 'Remote installer' {
    BeforeEach {
        $clone = Join-Path $TestDrive ("clone {0}" -f [guid]::NewGuid().ToString('N'))
        Mock Get-Command { [pscustomobject]@{ Source = "$Name.exe" } } -ParameterFilter {
            $Name -in @('git', 'winget') -and $CommandType -eq 'Application'
        }
        Mock git {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'clone') {
                New-TestClone -Path $args[-1]
            } elseif ($args[2] -eq 'remote') {
                'https://github.com/user3301/WhereZenZoo.git'
            } elseif ($args[2] -eq 'branch') {
                'main'
            }
        }
        Mock winget { throw 'WinGet must not run when Git is available' }
    }

    It 'clones without submodules and runs setup from a path containing spaces' {
        & $installer -Destination $clone
        Get-Content -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -Be 'BuildTools=False'
        Should -Invoke git -Times 1 -ParameterFilter {
            $args[0] -eq 'clone' -and $args -notcontains '--recurse-submodules'
        }
        Should -Invoke winget -Times 0
    }

    It 'forwards the optional BuildTools switch' {
        & $installer -Destination $clone -BuildTools
        Get-Content -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -Be 'BuildTools=True'
    }

    It 'fast-forwards a clean main checkout before running setup' {
        New-TestClone $clone
        & $installer -Destination $clone
        Should -Invoke git -Times 1 -ParameterFilter {
            $args[2] -eq 'pull' -and $args -contains '--ff-only'
        }
        Test-Path -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -BeTrue
    }

    It 'refuses a directory that is not a clone' {
        New-Item -ItemType Directory -Path $clone | Out-Null
        { & $installer -Destination $clone } | Should -Throw '*not a clone*'
        Should -Invoke git -Times 0
    }

    It 'refuses a different repository without updating or running it' {
        New-TestClone $clone
        Mock git {
            $global:LASTEXITCODE = 0
            'https://github.com/example/different.git'
        } -ParameterFilter { $args[2] -eq 'remote' }
        { & $installer -Destination $clone } | Should -Throw '*not a WhereZenZoo clone*'
        Should -Invoke git -Times 0 -ParameterFilter { $args[2] -eq 'pull' }
        Test-Path -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -BeFalse
    }

    It 'leaves a dirty checkout untouched' {
        New-TestClone $clone
        Mock git {
            $global:LASTEXITCODE = 0
            ' M powershell/profile.ps1'
        } -ParameterFilter { $args[2] -eq 'status' }
        { & $installer -Destination $clone } | Should -Throw '*uncommitted changes*'
        Should -Invoke git -Times 0 -ParameterFilter { $args[2] -eq 'pull' }
        Test-Path -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -BeFalse
    }

    It 'does not update a feature branch or a detached checkout' {
        New-TestClone $clone
        Mock git { $global:LASTEXITCODE = 0; 'feature' } -ParameterFilter { $args[2] -eq 'branch' }
        { & $installer -Destination $clone } | Should -Throw '*must be on main*'
        Should -Invoke git -Times 0 -ParameterFilter { $args[2] -eq 'pull' }
    }

    It 'stops after a failed clone' {
        Mock git { $global:LASTEXITCODE = 128 }
        { & $installer -Destination $clone } | Should -Throw '*Cloning failed*'
        Test-Path -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -BeFalse
    }

    It 'stops after a failed fast-forward instead of running stale setup' {
        New-TestClone $clone
        Mock git { $global:LASTEXITCODE = 128 } -ParameterFilter { $args[2] -eq 'pull' }
        { & $installer -Destination $clone } | Should -Throw '*Updating the clone failed*'
        Test-Path -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -BeFalse
    }

    It 'surfaces setup failure without exiting the caller' {
        New-TestClone $clone
        Set-Content -LiteralPath (Join-Path $clone 'setup.ps1') -Value 'exit 9'
        { & $installer -Destination $clone } | Should -Throw '*Setup failed (exit 9)*'
    }

    It 'does not leak preference variables when evaluated like the remote one-liner' {
        $originalHome = $env:USERPROFILE
        $before = $ErrorActionPreference
        $repo = 'caller-owned-variable'
        try {
            $env:USERPROFILE = Join-Path $TestDrive 'remote-user'
            Get-Content -LiteralPath $installer -Raw | Invoke-Expression
            $ErrorActionPreference | Should -Be $before
            $repo | Should -Be 'caller-owned-variable'
            Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'dotfiles\setup-ran.txt') | Should -BeTrue
        } finally {
            $env:USERPROFILE = $originalHome
        }
    }

    It 'fails clearly when WinGet is missing' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'winget' }
        { & $installer -Destination $clone } | Should -Throw '*App Installer*'
        Should -Invoke git -Times 0
    }

    It 'propagates failure to install the Git prerequisite' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'git' }
        Mock winget { $global:LASTEXITCODE = 5 }
        { & $installer -Destination $clone } | Should -Throw '*Installing Git failed*'
        Should -Invoke git -Times 0
    }

    It 'installs a missing Git prerequisite before cloning and preserves process PATH entries' {
        $originalPath = $env:PATH
        $script:gitReady = $false
        Mock Get-Command {
            if ($script:gitReady) { [pscustomobject]@{ Source = 'git.exe' } }
        } -ParameterFilter { $Name -eq 'git' }
        Mock winget { $script:gitReady = $true; $global:LASTEXITCODE = 0 }
        try {
            $env:PATH = 'C:\process-only-tools;' + $originalPath
            & $installer -Destination $clone
            $env:PATH.Split(';')[0] | Should -Be 'C:\process-only-tools'
            $env:PATH.Split(';') | Should -Contain (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
            Test-Path -LiteralPath (Join-Path $clone 'setup-ran.txt') | Should -BeTrue
            Should -Invoke winget -Times 1 -ParameterFilter {
                $args[0] -eq 'install' -and $args -contains 'Git.Git'
            }
        } finally {
            $env:PATH = $originalPath
        }
    }
}
