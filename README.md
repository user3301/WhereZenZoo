# WhereZenZoo

WhereZenZoo is a small Windows 11 development-environment bootstrapper built around [Scoop](https://scoop.sh/). It avoids WinGet so newly installed command-line tools are available through Scoop shims immediately after installation.

## Quick start

Open **Windows PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1 | iex
```

The installer will:

1. Install Scoop if it is missing
2. Install Git through Scoop if it is missing
3. Clone this repository to `~\dotfiles`
4. Hand off to `bootstrap.ps1`

## Manual install

```powershell
git clone https://github.com/user3301/WhereZenZoo.git $env:USERPROFILE\dotfiles
powershell.exe -ExecutionPolicy Bypass -File $env:USERPROFILE\dotfiles\bootstrap.ps1
```

## What gets installed

`bootstrap.ps1` ensures the core tools are present:

- Scoop
- Git
- PowerShell 7 (`pwsh`)
- `just`

`setup.ps1` then installs everything declared in `config/scoop.json`, links the PowerShell profile and fastfetch config, and installs PowerShell modules from `powershell/modules.json`.

## Common commands

```powershell
# Run the full setup
pwsh -ExecutionPolicy Bypass -File .\setup.ps1

# Only install Scoop packages
pwsh -ExecutionPolicy Bypass -File .\setup.ps1 -Packages

# Only refresh symlinks
pwsh -ExecutionPolicy Bypass -File .\setup.ps1 -Symlinks

# Remove symlinks, modules, and Scoop packages installed by this repo
pwsh -ExecutionPolicy Bypass -File .\uninstall.ps1
```

## Package configuration

Edit `config/scoop.json` to add or remove Scoop buckets and packages. Re-run `setup.ps1 -Packages` after changing it.

## Notes

- Do not run Scoop as Administrator; it is designed for per-user installs.
- Scoop shims live in `~\scoop\shims`; the scripts refresh the current session PATH after installs.
- Close and reopen Windows Terminal after setup so all environment changes are loaded by new shells.
