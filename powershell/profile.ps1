#Requires -Version 7.0

$env:PYTHONIOENCODING = 'utf-8'
. (Join-Path $PSScriptRoot 'aliases.ps1')

$zoxideCommand = Get-Command zoxide -CommandType Application -ErrorAction Ignore
if ($zoxideCommand) {
    try {
        $binary = Get-Item -LiteralPath $zoxideCommand.Source -ErrorAction Stop
        $stamp = "# $($binary.FullName)|$($binary.LastWriteTimeUtc.Ticks)|$($binary.Length)"
        $cacheDir = Join-Path $env:LOCALAPPDATA 'WhereZenZoo\cache'
        $cache = Join-Path $cacheDir 'zoxide-init.ps1'
        # Keep the binary stamp and generated code together, replacing the cache atomically.
        if (-not (Test-Path -LiteralPath $cache) -or
            (Get-Content -LiteralPath $cache -TotalCount 1 -ErrorAction Stop) -cne $stamp) {
            $init = & $zoxideCommand.Source init powershell
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($init -join ''))) {
                throw "zoxide init failed (exit $LASTEXITCODE)."
            }
            $code = $stamp + [Environment]::NewLine + ($init -join [Environment]::NewLine)
            $null = [scriptblock]::Create($code)
            New-Item -ItemType Directory -Path $cacheDir -Force -ErrorAction Stop | Out-Null
            $temporary = Join-Path $cacheDir ("zoxide-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
            try {
                [IO.File]::WriteAllText($temporary, $code)
                [IO.File]::Move($temporary, $cache, $true)
            } finally {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -ErrorAction Stop }
            }
        }
        . $cache
    } catch {
        Write-Warning "zoxide initialization failed: $_"
    }
}
