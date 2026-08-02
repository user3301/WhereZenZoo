# WhereZenZoo

![](./assets/lz-battle-robe.png)

> "WhereZenZoo('味儿真足'）- your Windows 11 dev environment, seasoned just right. PowerShell meets dotfiles swagger, no more clicking 'Next' like a peasant. 100% less mouse and 100% more 良子 energy."

WhereZenZoo is a small, **winget-based** Windows 11 bootstrapper for a lean **git + Neovim/LazyVim** workflow. No bloat: it installs only what LazyVim needs, symlinks your Neovim config, and sets up a [starship](https://starship.rs/) prompt.

## Prerequisites

- **Developer Mode enabled** — required so symlinks are created without admin. This
  applies to **both** PowerShell editions: PowerShell 7 honors Developer Mode directly,
  and under Windows PowerShell 5.1 the setup delegates symlink creation to `pwsh`.
  Without it (and without an elevated shell) the symlink step fails. Turn it on at
  Settings → System → For developers → Developer Mode.
- **winget** (App Installer) — ships with Windows 11; otherwise install "App Installer"
  from the Microsoft Store.

### Shell compatibility

The scripts run under **both Windows PowerShell 5.1 and PowerShell 7** — launch the
one-liner from either. PowerShell 7 (`pwsh`) is installed as one of the packages, and
on the 5.1 path it is what actually creates the symlinks: Windows PowerShell 5.1's own
`New-Item -SymbolicLink` ignores Developer Mode (it needs admin), so setup routes
symlink creation through pwsh.

## Quick start

Open **Windows PowerShell** and run the one-liner:

```powershell
irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1 | iex
```

It will:

1. Ensure winget and Git are available (installing Git via winget if missing).
2. Clone this repo (with the `dotfiles` submodule) to `~\dotfiles`.
3. Run `bootstrap.ps1` → `setup.ps1`.

## Uninstall

One-liner to revert the setup:

```powershell
irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/uninstall.ps1 | iex
```

This removes the symlinks (restoring any `.bak` backups) and uninstalls **only the
packages this setup installed**. Tools you already had are left alone. Add `-Purge`
(when run from a clone) to also delete LazyVim runtime data and the `~\dotfiles` clone:

```powershell
powershell -ExecutionPolicy Bypass -File ~\dotfiles\uninstall.ps1 -Purge
```

## What gets installed

Everything is declared in `config/packages.json` (standard `winget export` schema):

| Package | winget id | Why |
| --- | --- | --- |
| Git | `Git.Git` | version control + LazyVim |
| PowerShell 7 | `Microsoft.PowerShell` | daily shell (`pwsh`) |
| Neovim | `Neovim.Neovim` | the editor |
| fd | `sharkdp.fd` | LazyVim file finding |
| ripgrep | `BurntSushi.ripgrep.MSVC` | LazyVim grep |
| lazygit | `JesseDuffield.lazygit` | git TUI in Neovim |
| GNU Make | `ezwinports.make` | task runner (this repo's `Makefile`) |
| starship | `Starship.Starship` | shell prompt |
| MSVC Build Tools | `Microsoft.VisualStudio.2022.BuildTools` | C/C++ toolchain nvim-treesitter (main branch) needs to build parsers |

Your Neovim config comes from the **`dotfiles` submodule** (`submodules/dotfiles/nvim/.config/nvim`) and is symlinked to `%LOCALAPPDATA%\nvim`. The minimal PowerShell profile (`powershell/profile.ps1`) is symlinked into **both** the PowerShell 7 and Windows PowerShell `$PROFILE` locations, so starship + aliases load whichever shell you use. The git identity/config (`submodules/dotfiles/git/.config/git`) is symlinked to `%USERPROFILE%\.config\git`, so `user.name`, `user.email`, and other git settings are identical on every machine this setup runs on.

## Idempotency & safety

- **Re-runnable.** Run the setup as often as you like — installed packages and correct
  symlinks are skipped, so nothing is done twice.
- **Picks up changes.** Add a package id to `config/packages.json` and re-run; only the
  new one is installed.
- **Never overwrites your tools.** A package already present (on PATH or known to winget)
  is skipped. Uninstall only removes packages recorded as installed by this setup.
- **Existing configs are preserved.** An existing `%LOCALAPPDATA%\nvim`, `$PROFILE`, or
  `%USERPROFILE%\.config\git` is moved to `*.bak` before the symlink is created, and
  restored on uninstall.

## Common commands (after bootstrap installs `make`)

```powershell
make setup       # install packages + create symlinks
make packages    # install winget packages only
make symlinks    # create Neovim + profile symlinks only
make check       # validate .ps1 and .json files parse
make uninstall   # revert setup (symlinks + packages we installed)
```

> `make` is installed by the first bootstrap, so use the install one-liner on a fresh
> machine before reaching for `make`.

## Manual install

```powershell
git clone --recurse-submodules https://github.com/user3301/WhereZenZoo.git $env:USERPROFILE\dotfiles
powershell -ExecutionPolicy Bypass -File $env:USERPROFILE\dotfiles\bootstrap.ps1
```

## Notes

- The bootstrap runs under Windows PowerShell 5.1 (so it works before PowerShell 7 is
  installed); PowerShell 7 is then installed as a package and the profile is linked for
  both shells.
- winget shims live in `%LOCALAPPDATA%\Microsoft\WinGet\Links`; the scripts refresh the
  current session PATH after installs, but open a fresh terminal to pick up all changes.
