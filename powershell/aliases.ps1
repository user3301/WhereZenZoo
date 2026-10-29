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

function Invoke-GlazeWM {
    $application = Get-Command glazewm -CommandType Application -ErrorAction Stop
    $arguments = @($args)
    if ($arguments.Count -eq 0) { $arguments = @('start') }
    if ($arguments[0] -ceq 'start' -and
        $arguments -cnotcontains '--help' -and $arguments -cnotcontains '-h' -and
        -not ($arguments -cmatch '^(--config($|=)|-[vqh]*c)')) {
        if ([string]::IsNullOrWhiteSpace($env:GLAZEWM_CONFIG_PATH)) {
            throw 'GLAZEWM_CONFIG_PATH is not set. Load the dotfiles PowerShell profile or pass --config explicitly.'
        }
        # The Windows UIAccess launch may discard shell-local environment variables.
        $arguments += @('--config', $env:GLAZEWM_CONFIG_PATH)
    }
    & $application.Source @arguments
}

Set-Alias -Name glazewm -Value Invoke-GlazeWM
