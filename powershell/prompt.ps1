#Requires -Version 7.0

function global:Get-GitPromptBranch {
    param([Parameter(Mandatory)][string]$Path)

    $directory = [IO.DirectoryInfo]::new($Path)
    while ($null -ne $directory) {
        $gitPath = [IO.Path]::Combine($directory.FullName, '.git')
        if ([IO.Directory]::Exists($gitPath)) {
            $gitDir = $gitPath
        } elseif ([IO.File]::Exists($gitPath)) {
            $pointer = [IO.File]::ReadAllText($gitPath).Trim()
            if ($pointer -cnotmatch '^gitdir: (.+)$') {
                throw [FormatException]::new("Invalid gitdir pointer: $gitPath")
            }
            $gitDir = [IO.Path]::GetFullPath($Matches[1], $directory.FullName)
        } else {
            $directory = $directory.Parent
            continue
        }

        $head = [IO.File]::ReadAllText([IO.Path]::Combine($gitDir, 'HEAD')).Trim()
        if ($head -cmatch '^ref: refs/heads/(.+)$') { return $Matches[1] }
        if ($head -match '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
            return "detached:$($head.Substring(0, 7))"
        }
        throw [FormatException]::new("Invalid HEAD in $gitDir")
    }
}

# Do not discard mise/zoxide wrappers when the profile is loaded again.
if (-not (Get-Variable WhereZenZooPromptInstalled -Scope Global -ValueOnly -ErrorAction Ignore)) {
    function global:prompt {
        [CmdletBinding()]
        param()

        $previousSuccess = $?
        $previousExitCode = $global:LASTEXITCODE
        $text = "PS $PWD"
        try {
            if ($PWD.Provider.Name -eq 'FileSystem') {
                $branch = Get-GitPromptBranch -Path $PWD.ProviderPath
                if ($branch) { $text += " [$branch]" }
            }
        } catch [IO.IOException], [UnauthorizedAccessException], [ArgumentException], [NotSupportedException], [FormatException] {
            Write-Warning "Git prompt failed: $_"
        } finally {
            $global:LASTEXITCODE = $previousExitCode
        }
        # Preserve the failed-command status as well as the native exit code.
        if (-not $previousSuccess) {
            $ErrorActionPreference = 'Ignore'
            $record = [Management.Automation.ErrorRecord]::new(
                [Exception]::new('Previous command failed'), 'PreviousCommandFailed',
                [Management.Automation.ErrorCategory]::NotSpecified, $null)
            $PSCmdlet.WriteError($record)
        }
        "$text$('>' * ($nestedPromptLevel + 1)) "
    }
    $global:WhereZenZooPromptInstalled = $true
}
