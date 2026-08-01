# WhereZenZoo task runner (GNU Make).
# Recipes run under PowerShell 7 (pwsh), which honors Developer Mode for symlink
# creation (Windows PowerShell 5.1 does not). `make` and `pwsh` are both installed
# by setup (config/packages.json), so on a fresh machine bootstrap with the install
# one-liner first, then `make` targets are available.

PS := pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass

.PHONY: help setup packages symlinks check uninstall
.DEFAULT_GOAL := help

help:
	@$(PS) -Command "Write-Host 'WhereZenZoo make targets:'; Write-Host '  make setup      install winget packages + create symlinks'; Write-Host '  make packages   install winget packages only'; Write-Host '  make symlinks   create Neovim + profile symlinks only'; Write-Host '  make check      validate .ps1 and .json files parse'; Write-Host '  make uninstall  revert setup (symlinks + packages we installed)'"

setup:
	$(PS) -File ./setup.ps1

packages:
	$(PS) -File ./setup.ps1 -Packages

symlinks:
	$(PS) -File ./setup.ps1 -Symlinks

uninstall:
	$(PS) -File ./uninstall.ps1

check:
	$(PS) -Command "$$ErrorActionPreference='Stop'; $$skip='\\submodules\\|\\.git\\'; Get-ChildItem -Recurse -File -Include *.ps1 | Where-Object { $$_.FullName -notmatch $$skip } | ForEach-Object { $$t=$$null; $$e=$$null; [System.Management.Automation.Language.Parser]::ParseFile($$_.FullName,[ref]$$t,[ref]$$e) > $$null; if ($$e) { throw ('Parse errors in ' + $$_.FullName + ': ' + ($$e | Out-String)) } }; Get-ChildItem -Recurse -File -Include *.json | Where-Object { $$_.FullName -notmatch $$skip } | ForEach-Object { Get-Content -Raw $$_.FullName | ConvertFrom-Json > $$null }; Write-Host 'checks passed'"
	powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$$ErrorActionPreference='Stop'; $$skip='\\submodules\\|\\.git\\'; Get-ChildItem -Recurse -File -Include *.ps1 | Where-Object { $$_.FullName -notmatch $$skip } | ForEach-Object { $$t=$$null; $$e=$$null; [System.Management.Automation.Language.Parser]::ParseFile($$_.FullName,[ref]$$t,[ref]$$e) > $$null; if ($$e) { throw ('Windows PowerShell parse errors in ' + $$_.FullName + ': ' + ($$e | Out-String)) } }; Write-Host 'Windows PowerShell 5.1 checks passed'"
