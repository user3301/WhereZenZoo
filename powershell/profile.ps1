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
