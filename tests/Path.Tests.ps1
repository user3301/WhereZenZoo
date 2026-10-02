BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\common.ps1')
}

Describe 'PATH refresh' {
    It 'adds installed tool locations without discarding process-only entries' {
        $originalPath = $env:PATH
        try {
            $env:PATH = 'C:\process-only-tools'
            Update-SessionPath
            $env:PATH.Split(';')[0] | Should -Be 'C:\process-only-tools'
            $env:PATH.Split(';') | Should -Contain (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
        } finally {
            $env:PATH = $originalPath
        }
    }
}
