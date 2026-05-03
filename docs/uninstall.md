# Windows 11 Dotfiles — Uninstall Guide

## Overview

`uninstall.ps1` is the inverse of `setup.ps1` + `bootstrap.ps1`. It removes symlinks, restores backups, uninstalls PowerShell modules, cleans up font files, and uninstalls all WinGet packages installed by this repo.

All phases run by default. Pass individual flags to run a subset.

---

## Usage

```powershell
# Default: runs all phases (symlinks, modules, packages, fonts)
pwsh -ExecutionPolicy Bypass -File uninstall.ps1

# Equivalent explicit form
pwsh -ExecutionPolicy Bypass -File uninstall.ps1 -All

# Individual phases
pwsh -ExecutionPolicy Bypass -File uninstall.ps1 -Symlinks
pwsh -ExecutionPolicy Bypass -File uninstall.ps1 -Shell
pwsh -ExecutionPolicy Bypass -File uninstall.ps1 -Packages
pwsh -ExecutionPolicy Bypass -File uninstall.ps1 -Fonts
```

---

## Phases

| # | Flag | Default | What it reverses |
|---|------|---------|-----------------|
| 1 | `-Symlinks` | yes | Removes the three dotfile symlinks; restores `.bak` backups |
| 2 | `-Shell`    | yes | Uninstalls PSGallery modules from `powershell/modules.json` |
| 3 | `-Packages` | yes | Uninstalls all WinGet packages from `config/packages.json` + bootstrap tools |
| 4 | `-Fonts`    | yes | Removes Meslo Nerd Font files and `HKCU` registry entries |

---

## Phase Details

### Phase 1 — Symlinks

Removes the three symbolic links created by `setup.ps1 -Symlinks`. If a `.bak` file exists at the target path (left by the original setup), it is renamed back to the original, restoring the pre-setup state.

| Symlink | Target |
|---------|--------|
| `$PROFILE.CurrentUserAllHosts` | `powershell/profile.ps1` in repo |
| `$env:LOCALAPPDATA\nvim` | `submodules/dotfiles/nvim/.config/nvim` |
| `$env:USERPROFILE\.config\git` | `submodules/dotfiles/git/.config/git` |

If the path exists but is **not** a symlink, the phase skips it with a warning to avoid accidental data loss.

### Phase 2 — PowerShell Modules

Reads `powershell/modules.json` and calls `Uninstall-Module -AllVersions -Force` for each entry.

Modules removed:

| Module | Installed scope |
|--------|----------------|
| `PSReadLine` | CurrentUser |
| `Terminal-Icons` | CurrentUser |
| `z` | CurrentUser |

### Phase 3 — WinGet Packages (opt-in)

Calls `winget uninstall --exact --silent` for every package installed by `setup.ps1` and `bootstrap.ps1`. Treats non-zero exit codes as "not installed" and skips gracefully.

Packages targeted:

| Package ID | Tool |
|-----------|------|
| `Anthropic.ClaudeCode` | Claude Code |
| `BurntSushi.ripgrep.MSVC` | ripgrep |
| `JanDeDobbeleer.OhMyPosh` | Oh My Posh |
| `JesseDuffield.lazygit` | lazygit |
| `LLVM.LLVM` | LLVM / Clang |
| `Neovim.Neovim` | Neovim |
| `sharkdp.fd` | fd |
| `Casey.Just` | just |
| `Git.Git` | Git |
| `Microsoft.PowerShell` | PowerShell 7 |


### Phase 4 — Fonts

Enumerates `MesloLGM*NerdFont*.ttf` files under `$env:USERPROFILE\AppData\Local\Microsoft\Windows\Fonts`, removes each file, and deletes the corresponding `(TrueType)` value from `HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts`.

---

## Caveats

### `~/.gitconfig` cannot be restored

`setup.ps1` deleted `$env:USERPROFILE\.gitconfig` without creating a backup (the dotfiles git config under `~/.config/git` was intended to be the sole source of truth). After running the uninstaller, recreate it manually:

```powershell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

### Font changes take effect after terminal restart

Removing font registry entries does not force-unload a font that is currently in use. Close and reopen Windows Terminal (or reboot) to fully clear the Meslo Nerd Font from the system font list.

### Re-running setup after uninstall

`setup.ps1` is idempotent, so it is safe to re-run after `uninstall.ps1`. The setup will recreate symlinks, reinstall modules, and re-register fonts from scratch.
