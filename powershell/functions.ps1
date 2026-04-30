# Create a directory and cd into it — like `mkcd` in zsh
function mkcd {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# Go up N directories — like `..`, `...` in zsh
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Print PATH entries one per line — useful for debugging
function path { $env:PATH -split ';' }
