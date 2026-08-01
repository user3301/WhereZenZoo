# WhereZenZoo PowerShell profile — minimal, git + Neovim focused.

$ErrorActionPreference = 'Continue'

# Prompt: starship (installed via config/packages.json).
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

# Sensible line-editing defaults (PSReadLine ships with PowerShell).
Set-PSReadLineOption -EditMode Windows -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue

Set-Alias vim nvim -ErrorAction SilentlyContinue
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
