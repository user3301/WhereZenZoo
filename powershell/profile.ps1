$ErrorActionPreference = 'Continue'

$repoProfileDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$promptTheme = Join-Path $repoProfileDir 'theme.omp.json'

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config $promptTheme | Invoke-Expression
}

if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

if (Get-Module -ListAvailable -Name z) {
    Import-Module z
}

Set-PSReadLineOption -EditMode Windows -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
Set-Alias vim nvim -ErrorAction SilentlyContinue
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
