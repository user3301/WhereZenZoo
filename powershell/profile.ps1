$ProfileRoot = Split-Path (Get-Item $PSCommandPath).Target

# --- Modules ---
Import-Module Terminal-Icons
Import-Module z

# --- PSReadLine ---
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# --- Git Unix tools (provides `file` for yazi MIME detection, etc.) ---
$gitRoot = Split-Path (Split-Path (Get-Command git -ErrorAction SilentlyContinue).Source)
$gitUnixBin = Join-Path $gitRoot "usr\bin"
if (Test-Path $gitUnixBin) {
    $env:PATH = "$env:PATH;$gitUnixBin"
}

# --- Load profile components ---
. "$ProfileRoot\aliases.ps1"
. "$ProfileRoot\functions.ps1"
. "$ProfileRoot\prompt.ps1"

# --- Zellij auto-start (skip in elevated/admin sessions) ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $env:ZELLIJ -and (Get-Command zellij -ErrorAction SilentlyContinue)) {
    if ($env:ZELLIJ_AUTO_ATTACH -eq 'true') {
        zellij attach -c
    } else {
        zellij
    }
    if ($LASTEXITCODE -eq 0 -and $env:ZELLIJ_AUTO_EXIT -eq 'true') {
        exit
    }
}
