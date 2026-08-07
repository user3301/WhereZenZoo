# WhereZenZoo PowerShell profile — minimal, git + Neovim focused.

Invoke-Expression (& { (zoxide init powershell | Out-String) })

$aliasesPath = Join-Path (Join-Path $HOME 'powershell') 'aliases.ps1'
. $aliasesPath
