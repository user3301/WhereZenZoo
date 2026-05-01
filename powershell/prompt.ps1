# Initialise oh-my-posh with the jandedobbeleer theme
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "$ProfileRoot\themes\jandedobbeleer.omp.json" | Invoke-Expression
}
