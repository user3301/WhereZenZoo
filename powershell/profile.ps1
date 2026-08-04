# WhereZenZoo PowerShell profile — minimal, git + Neovim focused.

$ErrorActionPreference = 'Continue'

# Prompt: starship (installed via config/packages.json).
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
}

# Sensible line-editing defaults (PSReadLine ships with PowerShell).
# -PredictionSource needs PSReadLine 2.2+ (PowerShell 7); Windows PowerShell 5.1's
# bundled PSReadLine 2.0.0 lacks it, and a missing parameter is a terminating
# binding error that -ErrorAction can't suppress, so gate it explicitly.
try {
    $cmd = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Parameters.ContainsKey('PredictionSource')) {
        Set-PSReadLineOption -EditMode Windows -PredictionSource HistoryAndPlugin
    } elseif ($cmd) {
        Set-PSReadLineOption -EditMode Windows
    }
} catch {
    # PSReadLine unavailable or misbehaving; skip silently.
}

$aliasesPath = Join-Path (Join-Path $HOME 'powershell') 'aliases.ps1'
. $aliasesPath
