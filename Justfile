# WhereZenZoo task runner

default:
    @just --list

setup:
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./setup.ps1

packages:
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ./setup.ps1 -Packages

check:
    pwsh -NoLogo -NoProfile -Command '$$ErrorActionPreference="Stop"; Get-ChildItem -Recurse -File -Include *.ps1 | ForEach-Object { $$tokens=$$null; $$errors=$$null; [System.Management.Automation.Language.Parser]::ParseFile($$_.FullName, [ref]$$tokens, [ref]$$errors) > $$null; if ($$errors) { throw "Parse errors in $$($$_.FullName): $$($$errors | Out-String)" } }; Get-ChildItem -Recurse -File -Include *.json | ForEach-Object { Get-Content -Raw $$_.FullName | ConvertFrom-Json > $$null }; "checks passed"'
