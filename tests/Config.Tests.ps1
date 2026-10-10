BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
    function winget { throw 'Tests must not invoke the real WinGet executable' }
}

Describe 'Live configuration and rollback' {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $source = Join-Path $caseRoot "repo [test] O'Brien"
        $destination = Join-Path $caseRoot 'home\config'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $source 'settings.txt') -Value 'repo'
        $config = @{ Kind = 'Junction'; Path = $destination; Target = $source }
    }

    AfterEach {
        $item = Get-Item -LiteralPath $destination -Force -ErrorAction Ignore
        if ($item.LinkType -in @('Junction', 'SymbolicLink')) {
            Remove-ConfigLink $item
        }
    }

    It 'creates a live junction without symbolic-link privileges' {
        Install-Dotfile $config
        (Get-Item -LiteralPath $destination).LinkType | Should -Be 'Junction'
        Get-Content -LiteralPath (Join-Path $destination 'settings.txt') | Should -Be 'repo'
        Set-Content -LiteralPath (Join-Path $source 'settings.txt') -Value 'changed'
        Get-Content -LiteralPath (Join-Path $destination 'settings.txt') | Should -Be 'changed'
    }

    It 'is idempotent and keeps the first backup' {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'original.txt') -Value 'original'
        Install-Dotfile $config
        Install-Dotfile $config
        Get-Content -LiteralPath "$destination.wherezenzoo-backup\original.txt" | Should -Be 'original'
        @(Get-ChildItem -LiteralPath (Split-Path $destination) -Filter '*.wherezenzoo-backup').Count |
            Should -Be 1
    }

    It 'restores a pre-existing directory without deleting repository content' {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'original.txt') -Value 'original'
        Install-Dotfile $config
        Remove-Dotfile $config
        (Get-Item -LiteralPath $destination).LinkType | Should -BeNullOrEmpty
        Get-Content -LiteralPath (Join-Path $destination 'original.txt') | Should -Be 'original'
        Test-Path -LiteralPath (Join-Path $source 'settings.txt') | Should -BeTrue
        Test-Path -LiteralPath "$destination.wherezenzoo-backup" | Should -BeFalse
    }

    It 'materializes the old link backup so removing its source cannot break rollback' {
        $oldSource = Join-Path $caseRoot 'old-submodule'
        New-Item -ItemType Directory -Path $oldSource -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $oldSource 'original.txt') -Value 'old settings'
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $oldSource | Out-Null
        Install-Dotfile $config
        (Get-Item -LiteralPath "$destination.wherezenzoo-backup").LinkType | Should -BeNullOrEmpty
        Remove-Item -LiteralPath (Join-Path $oldSource 'original.txt')
        Remove-Dotfile $config
        Get-Content -LiteralPath (Join-Path $destination 'original.txt') | Should -Be 'old settings'
    }

    It 'replaces a dangling junction and preserves it for rollback (chained=<Chained>)' -ForEach @(
        @{ Chained = $false }
        @{ Chained = $true }
    ) {
        $missing = Join-Path $caseRoot 'submodules\dotfiles\nvim\.config\nvim'
        New-Item -ItemType Directory -Path $missing -Force | Out-Null
        $oldTarget = $missing
        if ($Chained) {
            $oldTarget = Join-Path $caseRoot 'intermediate'
            New-Item -ItemType Junction -Path $oldTarget -Target $missing | Out-Null
        }
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $oldTarget | Out-Null
        [IO.Directory]::Delete($missing, $false)
        try {
            Install-Dotfile $config -WarningVariable warnings
            ($warnings -join ' ') | Should -Match 'missing'
            Test-Dotfile $config | Should -BeTrue
            Get-Content -LiteralPath (Join-Path $destination 'settings.txt') | Should -Be 'repo'
            (Get-Item -LiteralPath "$destination.wherezenzoo-backup" -Force).Target | Should -Be $oldTarget
            Install-Dotfile $config
            (Get-Item -LiteralPath "$destination.wherezenzoo-backup" -Force).Target | Should -Be $oldTarget
            Remove-Dotfile $config
            (Get-Item -LiteralPath $destination -Force).Target | Should -Be $oldTarget
            Get-Item -LiteralPath "$destination.wherezenzoo-backup" -Force -ErrorAction Ignore |
                Should -BeNullOrEmpty
            Test-Path -LiteralPath $missing | Should -BeFalse
        } finally {
            if ($Chained) { Remove-ConfigLink (Get-Item -LiteralPath $oldTarget -Force) }
        }
    }

    It 'restores a dangling junction if creating the replacement fails' {
        $missing = Join-Path $caseRoot 'missing'
        New-Item -ItemType Directory -Path $missing | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $missing | Out-Null
        [IO.Directory]::Delete($missing, $false)
        Mock New-Item { throw 'simulated junction failure' } -ParameterFilter { $ItemType -eq 'Junction' }
        { Install-Dotfile $config } | Should -Throw '*simulated junction failure*'
        (Get-Item -LiteralPath $destination -Force).Target | Should -Be $missing
        Get-Item -LiteralPath "$destination.wherezenzoo-backup" -Force -ErrorAction Ignore |
            Should -BeNullOrEmpty
    }

    It 'does not overwrite an existing backup when the conflicting junction is dangling' {
        $missing = Join-Path $caseRoot 'missing'
        New-Item -ItemType Directory -Path $missing | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $missing | Out-Null
        [IO.Directory]::Delete($missing, $false)
        New-Item -ItemType Directory -Path "$destination.wherezenzoo-backup" | Out-Null
        Set-Content -LiteralPath "$destination.wherezenzoo-backup\original.txt" -Value 'original'
        { Install-Dotfile $config } | Should -Throw '*backup already exists*'
        (Get-Item -LiteralPath $destination -Force).Target | Should -Be $missing
        Get-Content -LiteralPath "$destination.wherezenzoo-backup\original.txt" | Should -Be 'original'
    }

    It 'does not treat access errors while resolving a link as a missing target' {
        $oldTarget = Join-Path $caseRoot 'inaccessible'
        New-Item -ItemType Directory -Path $oldTarget | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $oldTarget | Out-Null
        Mock Get-Item { throw [UnauthorizedAccessException]::new('simulated access denied') } -ParameterFilter {
            $LiteralPath -eq $oldTarget
        }
        { Install-Dotfile $config } | Should -Throw '*simulated access denied*'
        (Get-Item -LiteralPath $destination -Force).Target | Should -Be $oldTarget
        Get-Item -LiteralPath "$destination.wherezenzoo-backup" -Force -ErrorAction Ignore |
            Should -BeNullOrEmpty
    }

    It 'refuses to overwrite a backup after someone replaces a managed config' {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'original.txt') -Value 'original'
        Install-Dotfile $config
        [IO.Directory]::Delete($destination, $false)
        New-Item -ItemType Directory -Path $destination | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'replacement.txt') -Value 'replacement'
        { Install-Dotfile $config } | Should -Throw '*backup*'
        Get-Content -LiteralPath "$destination.wherezenzoo-backup\original.txt" | Should -Be 'original'
        Get-Content -LiteralPath (Join-Path $destination 'replacement.txt') | Should -Be 'replacement'
    }

    It 'does not uninstall a link that someone has retargeted' {
        $other = Join-Path $caseRoot 'other'
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType Junction -Path $destination -Target $other | Out-Null
        { Remove-Dotfile $config } | Should -Throw '*changed*'
        (Get-Item -LiteralPath $destination).Target | Should -Be $other
    }

    It 'removes a dangling managed junction without touching its old source' {
        Install-Dotfile $config
        Remove-Item -LiteralPath (Join-Path $source 'settings.txt')
        [IO.Directory]::Delete($source, $false)
        Remove-Dotfile $config
        Get-Item -LiteralPath $destination -Force -ErrorAction Ignore | Should -BeNullOrEmpty
    }

    It 'fails before replacing anything when a source is missing' {
        $config.Target = Join-Path $caseRoot 'missing'
        { Install-Dotfile $config } | Should -Throw '*source*'
        Test-Path -LiteralPath $destination | Should -BeFalse
    }

    It 'writes a literal-path profile loader and restores the original profile' {
        $destination += '.ps1'
        $config.Path = $destination
        $config.Kind = 'Profile'
        $config.Target = Join-Path $source 'profile.ps1'
        Set-Content -LiteralPath $config.Target -Value '$global:DotfilesProfileTest = ''loaded'''
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        Set-Content -LiteralPath $destination -Value '# original profile'
        Install-Dotfile $config
        Install-Dotfile $config
        . $destination
        $global:DotfilesProfileTest | Should -Be 'loaded'
        Remove-Variable -Name DotfilesProfileTest -Scope Global
        Remove-Dotfile $config
        (Get-Content -LiteralPath $destination -Raw).Trim() | Should -Be '# original profile'
    }

    It 'leaves an edited profile loader intact on uninstall' {
        $destination += '.ps1'
        $config.Path = $destination
        $config.Kind = 'Profile'
        $config.Target = Join-Path $source 'profile.ps1'
        Set-Content -LiteralPath $config.Target -Value '# repo profile'
        Install-Dotfile $config
        Add-Content -LiteralPath $destination -Value '# personal edit'
        { Remove-Dotfile $config } | Should -Throw '*changed*'
        Get-Content -LiteralPath $destination -Raw | Should -Match 'personal edit'
    }

    It 'preserves a linked profile for rollback (missing=<Missing>)' -ForEach @(
        @{ Missing = $false }
        @{ Missing = $true }
    ) {
        $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        $developerMode = Get-ItemPropertyValue -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
            -Name AllowDevelopmentWithoutDevLicense -ErrorAction Ignore
        if ($developerMode -ne 1 -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Set-ItResult -Skipped -Because 'Only this legacy-symlink fixture needs Developer Mode or elevation.'
            return
        }
        $destination += '.ps1'
        $config.Path = $destination
        $config.Kind = 'Profile'
        $config.Target = Join-Path $source 'profile.ps1'
        Set-Content -LiteralPath $config.Target -Value 'Get-Content -LiteralPath (Join-Path $PSScriptRoot ''settings.txt'')'
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $destination -Target $config.Target | Out-Null
        $oldTarget = $config.Target
        if ($Missing) {
            Remove-Item -LiteralPath $oldTarget
            $config.Target = Join-Path $source 'new-profile.ps1'
            Set-Content -LiteralPath $config.Target -Value '# repo profile'
        }
        Install-Dotfile $config
        Test-Dotfile $config | Should -BeTrue
        Install-Dotfile $config
        Remove-Dotfile $config
        if ($Missing) {
            (Get-Item -LiteralPath $destination -Force).LinkType | Should -Be 'SymbolicLink'
            (Get-Item -LiteralPath $destination -Force).Target | Should -Be $oldTarget
            Test-Path -LiteralPath $oldTarget | Should -BeFalse
        } else {
            (. $destination) | Should -Be 'repo'
            { Remove-Dotfile $config } | Should -Throw '*changed*'
            (. $destination) | Should -Be 'repo'
        }
    }

    It 'restores the original if creating the replacement fails' {
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $destination 'original.txt') -Value 'original'
        Mock New-Item { throw 'simulated junction failure' } -ParameterFilter { $ItemType -eq 'Junction' }
        { Install-Dotfile $config } | Should -Throw '*simulated junction failure*'
        Get-Content -LiteralPath (Join-Path $destination 'original.txt') | Should -Be 'original'
    }
}

Describe 'Configuration-only setup' {
    BeforeEach {
        $originalHome = $env:USERPROFILE
        $originalLocalAppData = $env:LOCALAPPDATA
        $env:USERPROFILE = Join-Path $TestDrive 'user'
        $env:LOCALAPPDATA = Join-Path $TestDrive 'local'
        $PROFILE = [pscustomobject]@{
            CurrentUserAllHosts = Join-Path $TestDrive 'OneDrive\Documents\PowerShell\profile.ps1'
        }
        $module = Join-Path (Split-Path $PROFILE.CurrentUserAllHosts) 'Modules\Existing\Existing.psm1'
        New-Item -ItemType Directory -Path (Split-Path $module) -Force | Out-Null
        Set-Content -LiteralPath $module -Value '# existing module'
        Mock Get-ExecutionPolicy { 'RemoteSigned' }
    }

    AfterEach {
        & (Join-Path $PSScriptRoot '..\uninstall.ps1')
        $env:USERPROFILE = $originalHome
        $env:LOCALAPPDATA = $originalLocalAppData
    }

    It 'sets up twice and rolls back without winget or relocating the module directory' {
        Mock winget { throw 'Config-only setup must not call winget' }
        & (Join-Path $PSScriptRoot '..\setup.ps1') -SkipPackages
        & (Join-Path $PSScriptRoot '..\setup.ps1') -SkipPackages
        (Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'nvim')).LinkType | Should -Be 'Junction'
        (Get-Item -LiteralPath (Join-Path $env:USERPROFILE '.config\git')).LinkType | Should -Be 'Junction'
        Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts | Should -BeTrue
        (Get-Item -LiteralPath (Split-Path $PROFILE.CurrentUserAllHosts)).LinkType | Should -BeNullOrEmpty
        Get-Content -LiteralPath $module | Should -Be '# existing module'
        Should -Invoke winget -Times 0
    }

    It 'completes configuration setup with a dangling legacy Neovim junction' {
        $nvim = Join-Path $env:LOCALAPPDATA 'nvim'
        $missing = Join-Path $env:USERPROFILE 'dotfiles\submodules\dotfiles\nvim\.config\nvim'
        New-Item -ItemType Directory -Path $missing -Force | Out-Null
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        New-Item -ItemType Junction -Path $nvim -Target $missing | Out-Null
        [IO.Directory]::Delete($missing, $false)
        & (Join-Path $PSScriptRoot '..\setup.ps1') -SkipPackages
        & (Join-Path $PSScriptRoot '..\setup.ps1') -SkipPackages
        (Get-LinkTarget (Get-Item -LiteralPath $nvim)) |
            Should -Be ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\nvim')))
        Test-Path -LiteralPath (Join-Path $nvim 'init.lua') | Should -BeTrue
        (Get-Item -LiteralPath "$nvim.wherezenzoo-backup" -Force).Target | Should -Be $missing
        Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts | Should -BeTrue
        Get-Content -LiteralPath $module | Should -Be '# existing module'
    }
}

Describe 'Persistent execution policy' {
    It 'does not mistake the installer process Bypass for permission to load future profiles' {
        Mock Get-ExecutionPolicy {
            if ($Scope -eq 'Process') { 'Bypass' } else { 'Undefined' }
        }
        { Assert-ProfileExecutionPolicy } | Should -Throw '*blocks the unsigned profile*'
    }

    It 'respects organization policy over the per-user setting' {
        Mock Get-ExecutionPolicy { 'RemoteSigned' }
        Mock Get-ExecutionPolicy { 'AllSigned' } -ParameterFilter { $Scope -eq 'MachinePolicy' }
        { Assert-ProfileExecutionPolicy } | Should -Throw '*signing policy*'
    }

    It 'accepts a per-user RemoteSigned policy without changing it' {
        Mock Get-ExecutionPolicy {
            if ($Scope -eq 'CurrentUser') { 'RemoteSigned' } else { 'Undefined' }
        }
        Mock Set-ExecutionPolicy { throw 'Policy must not be changed' }
        { Assert-ProfileExecutionPolicy } | Should -Not -Throw
        Should -Invoke Set-ExecutionPolicy -Times 0
    }
}
