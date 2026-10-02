BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
}

Describe 'Machine-local Git configuration' {
    BeforeEach {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $directory | Out-Null
        $source = Join-Path $directory 'existing.local'
        $target = Join-Path $directory 'repo.local'
        Set-Content -LiteralPath $source -Value '[commit]'
    }

    It 'preflights without copying and preserves the local config during setup' {
        Copy-GitLocalConfig -Source $source -Target $target -CheckOnly
        Test-Path -LiteralPath $target | Should -BeFalse
        Copy-GitLocalConfig -Source $source -Target $target
        Copy-GitLocalConfig -Source $source -Target $target
        (Get-FileHash -LiteralPath $source).Hash | Should -Be (Get-FileHash -LiteralPath $target).Hash
    }

    It 'refuses to overwrite different local settings even during preflight' {
        Set-Content -LiteralPath $target -Value '[user]'
        { Copy-GitLocalConfig -Source $source -Target $target -CheckOnly } | Should -Throw '*Two different*'
        { Copy-GitLocalConfig -Source $source -Target $target } | Should -Throw '*Two different*'
        Get-Content -LiteralPath $target | Should -Be '[user]'
    }

    It 'treats absent machine-local settings as optional' {
        Copy-GitLocalConfig -Source (Join-Path $directory 'missing.local') -Target $target
        Test-Path -LiteralPath $target | Should -BeFalse
    }
}
