$ProfileRoot = Split-Path (Get-Item $PSCommandPath).Target

# --- Modules ---
Import-Module Terminal-Icons
Import-Module z

# --- PSReadLine ---
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# --- Load profile components ---
. "$ProfileRoot\aliases.ps1"
. "$ProfileRoot\functions.ps1"
. "$ProfileRoot\prompt.ps1"

# --- Zellij auto-start ---
if (-not $env:ZELLIJ -and (Get-Command zellij -ErrorAction SilentlyContinue)) {
    if ($env:ZELLIJ_AUTO_ATTACH -eq 'true') {
        zellij attach -c
    } else {
        zellij
    }
    if ($env:ZELLIJ_AUTO_EXIT -eq 'true') {
        exit
    }
}
