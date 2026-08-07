Set-Alias v nvim -ErrorAction SilentlyContinue
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue

function Invoke-AgencyCopilot {
    agency copilot @args
}

Set-Alias copilot Invoke-AgencyCopilot -ErrorAction SilentlyContinue
