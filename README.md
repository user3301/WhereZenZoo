# WhereZenZoo

![](./assets/lz-battle-robe.png)

> "WhereZenZoo('味儿真足'）- your Windows 11 dev environment, seasoned just right. PowerShell meets dotfiles swagger, no more clicking 'Next' like a peasant. 100% less mouse and 100% more 良子 energy."

## Quick Start

Fresh Windows 11 machine? One line does everything — no git required.

### Prerequisites

- Windows 11
- [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) (provides `winget`) — ships by default on Windows 11, install from the Microsoft Store if missing

### One-liner (recommended)

Open **Windows PowerShell** (Win + X → "Windows PowerShell") and run:

```powershell
irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1 | iex
```

A UAC prompt will appear once to elevate. The script will then:

1. Install Git via winget
2. Clone this repo to `~\dotfiles`
3. Hand off to `bootstrap.ps1`, which installs PowerShell 7, `just`, and runs `setup.ps1`

### Manual steps (if you already have git)

**1. Clone this repo**

```powershell
git clone https://github.com/user3301/WhereZenZoo.git $env:USERPROFILE\dotfiles
```

**2. Run bootstrap**

```powershell
powershell.exe -ExecutionPolicy Bypass -File $env:USERPROFILE\dotfiles\bootstrap.ps1
```

A UAC prompt will appear once to elevate. After that, the script will:

- Install PowerShell 7 (if not already installed)
- Re-launch itself under PowerShell 7
- Install `just` (task runner)
- Hand off to `setup.ps1`

**3. What `setup.ps1` does automatically**

| Phase | What happens |
|---|---|
| 0 — Submodules | Initialises `submodules/dotfiles` (nvim, git config, …) |
| 1 — Validate | Checks PowerShell 7 and `winget` are available |
| 2 — Packages | Installs all WinGet packages (Neovim, Git, oh-my-posh, ripgrep, fd, lazygit, LLVM, …) and Meslo Nerd Font |
| 3 — Symlinks | Creates symlinks for PowerShell profile, Neovim config, and Git config |
| 4 — Shell | Installs PowerShell modules (Terminal-Icons, z, PSReadLine, …) |

**4. After setup completes**

- Close and reopen Windows Terminal
- Set the font to **MesloLGM Nerd Font** under Windows Terminal settings → Defaults → Appearance (required for oh-my-posh icons)
- Launch `nvim` once — LazyVim will bootstrap and install all plugins automatically

### Re-running

`bootstrap.ps1` and `setup.ps1` are fully idempotent — safe to re-run at any time to apply new changes or set up an additional machine.

## Uninstallation

To clean up everything installed by this repo, run the provided uninstall script:

```powershell
pwsh -ExecutionPolicy Bypass -File $env:USERPROFILE\dotfiles\uninstall.ps1
```

This removes symlinks, PowerShell modules, WinGet packages, and fonts.
