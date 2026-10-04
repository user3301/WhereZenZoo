#Requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$files = Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }
foreach ($file in $files) {
    if ($file.Extension -eq '.ps1') {
        $tokens = $null
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors) { throw "Parse errors in $($file.FullName): $($errors -join '; ')" }
    } elseif ($file.Extension -eq '.json') {
        $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    }
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $PSScriptRoot 'tests'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Normal'
$configuration.TestResult.Enabled = $false
$result = Invoke-Pester -Configuration $configuration
if ($result.Result -ne 'Passed') { throw 'PowerShell regression tests failed.' }

if (Get-Command nvim -CommandType Application -ErrorAction Ignore) {
    & nvim --headless -u NONE -i NONE -n -l (Join-Path $PSScriptRoot 'tests\nvim.lua') $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw "Neovim checks failed (exit $LASTEXITCODE)." }
} else {
    Write-Warning 'Neovim is not installed; Lua checks were not run.'
}
Write-Host 'Checks passed.' -ForegroundColor Green
