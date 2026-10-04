#Requires -Version 7.0

Set-Alias -Name v -Value nvim
Set-Alias -Name ll -Value Get-ChildItem

function Invoke-Copilot {
    $agency = Get-Command agency -CommandType Application -ErrorAction Ignore
    if ($agency) {
        & $agency.Source copilot @args
    } else {
        $standalone = Get-Command copilot -CommandType Application -ErrorAction Stop
        & $standalone.Source @args
    }
}

Set-Alias -Name copilot -Value Invoke-Copilot
