# Windows 11 Dotfiles — Architecture Plan

## Repo Structure

```
windows-dotfiles/
├── bootstrap.ps1                  # One-liner entry point
├── setup.ps1                      # Main orchestrator (phase-based runner)
│
├── config/
│   ├── packages.json              # WinGet declarative manifest (winget import target)
│   ├── scoop-packages.json        # Scoop buckets + packages
│   ├── wsl.conf                   # → /etc/wsl.conf inside WSL distro
│   ├── .wslconfig                 # → $HOME\.wslconfig (WSL2 VM resource limits)
│   └── settings.json              # Windows Terminal settings (symlinked)
│
├── powershell/
│   ├── profile.ps1                # $PROFILE content (dot-sourced via stub)
│   ├── aliases.ps1
│   ├── functions.ps1
│   ├── prompt.ps1                 # Starship/Oh-My-Posh loader
│   └── modules.json               # PSGallery modules to install declaratively
│
├── git/
│   ├── .gitconfig                 # → ~\.gitconfig
│   └── .gitignore_global
│
├── ssh/
│   └── config                     # → ~\.ssh\config (keys never committed)
│
├── wsl/
│   ├── bootstrap-wsl.sh           # Run inside WSL2 after distro provisioned
│   ├── packages-apt.txt           # apt packages list (one per line)
│   └── dotfiles-wsl/              # Bash/Zsh dotfiles pushed into WSL home
│       ├── .bashrc
│       ├── .zshrc
│       └── .aliases
│
├── scripts/
│   ├── Install-Packages.ps1
│   ├── Install-PSModules.ps1
│   ├── Set-Symlinks.ps1
│   ├── Set-WindowsSettings.ps1
│   ├── Install-WSL.ps1
│   └── Set-SshAgent.ps1
│
└── docs/
    ├── plan.md                    # This file
    └── MANUAL_STEPS.md            # Things that cannot be automated
```

---

## Package Manager: WinGet (primary) + Scoop (overflow)

- **WinGet**: Microsoft-native, ships with Windows 11. `winget import/export` gives a first-class declarative manifest. Use `--exact --id` for deterministic installs.
- **Scoop**: Unix-lineage CLI tools (`fzf`, `bat`, `ripgrep`, `delta`, `lazygit`). Zero UAC prompts, installs to `~\scoop\`, clean uninstall via `rm -rf` equivalent.
- **No Chocolatey**: WinGet + Scoop cover everything without the inconsistent community packages or paid repo tier.

---

## Bootstrap One-Liner

Run in PowerShell on a fresh machine:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; irm https://raw.githubusercontent.com/YOU/windows-dotfiles/main/bootstrap.ps1 | iex
```

`bootstrap.ps1` sequence:
1. Check for admin; re-launch elevated if needed
2. Install PowerShell 7 via `winget` if not present
3. Install Git via `winget` if not present
4. Clone repo to `$HOME\.dotfiles\`
5. Hand off to `setup.ps1` via `pwsh` (PS7, not PS5.1)

---

## `setup.ps1` — Phase-Based Orchestrator

```
setup.ps1 [-All] [-Packages] [-Shell] [-Symlinks] [-WSL] [-WindowsSettings] [-Force]
```

Phases run in order. Every phase is idempotent (`Test-X` before `Set-X`). Elevation is done inline per-phase, not for the entire script.

| # | Phase | Notes |
|---|---|---|
| 1 | Validate-Prerequisites | PS7 version, execution policy, internet |
| 2 | Install-Packages | WinGet first, then Scoop |
| 3 | Install-PSModules | Depends on PS7 being current |
| 4 | Set-Symlinks | Dotfile links into `$HOME` |
| 5 | Set-WindowsSettings | Registry tweaks, Developer Mode, Explorer settings |
| 6 | Install-WSL | Requires Hyper-V/VMP feature, may reboot |
| 7 | Set-SshAgent | Requires OpenSSH optional feature |
| 8 | Show-Summary | What succeeded, what needs manual steps |

---

## Declarative Package Definitions

### `config/packages.json` — WinGet native format

Generated via `winget export -o packages.json`. Consumed via `winget import`.

```json
{
  "$schema": "https://aka.ms/winget-packages.schema.2.0.json",
  "CreationDate": "2025-01-01T00:00:00.000-00:00",
  "Sources": [
    {
      "Packages": [
        { "PackageIdentifier": "Git.Git" },
        { "PackageIdentifier": "Microsoft.PowerShell" },
        { "PackageIdentifier": "Microsoft.WindowsTerminal" },
        { "PackageIdentifier": "Microsoft.VisualStudioCode" },
        { "PackageIdentifier": "Docker.DockerDesktop" },
        { "PackageIdentifier": "Starship.Starship" },
        { "PackageIdentifier": "GitHub.cli" },
        { "PackageIdentifier": "OpenJS.NodeJS.LTS" },
        { "PackageIdentifier": "Python.Python.3.12" }
      ],
      "SourceDetails": {
        "Argument": "https://cdn.winget.microsoft.com/cache",
        "Identifier": "Microsoft.Winget.Source_8wekyb3d8bbwe",
        "Name": "winget",
        "Type": "Microsoft.PreIndexed.Package"
      }
    }
  ],
  "WinGetVersion": "1.6.0"
}
```

Do not pin versions unless there is a hard requirement — WinGet resolves to latest by default.

### `config/scoop-packages.json` — custom schema

Scoop has no native import format. Define a custom schema interpreted by `Install-Packages.ps1`.

```json
{
  "buckets": [
    "main",
    "extras",
    "versions"
  ],
  "packages": [
    { "name": "fzf",       "bucket": "main" },
    { "name": "ripgrep",   "bucket": "main" },
    { "name": "bat",       "bucket": "main" },
    { "name": "delta",     "bucket": "main" },
    { "name": "lazygit",   "bucket": "extras" },
    { "name": "nvm",       "bucket": "main" },
    { "name": "jq",        "bucket": "main" }
  ]
}
```

### `powershell/modules.json` — PSGallery modules

```json
{
  "modules": [
    { "name": "PSReadLine",      "scope": "CurrentUser" },
    { "name": "posh-git",        "scope": "CurrentUser" },
    { "name": "Terminal-Icons",  "scope": "CurrentUser" },
    { "name": "z",               "scope": "CurrentUser" }
  ]
}
```

---

## PowerShell Profile Strategy

`$PROFILE` resolves to different paths per host. Use `CurrentUserAllHosts`:
`$HOME\Documents\PowerShell\profile.ps1`

This file is a **stub** written by `Set-Symlinks.ps1` that dot-sources the repo:

```powershell
# Auto-generated by dotfiles setup — do not edit directly
. "$HOME\.dotfiles\powershell\profile.ps1"
```

Profile load order in `powershell/profile.ps1`:
1. `aliases.ps1`
2. `functions.ps1`
3. `prompt.ps1`

---

## Symlink Strategy

- Symlinks require Developer Mode enabled OR admin. Enable Developer Mode via registry in `Set-WindowsSettings.ps1` first.
- Registry key: `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock` → `AllowDevelopmentWithoutDevLicense = 1`
- Symlink map is declared as a data structure in `Set-Symlinks.ps1`, not scattered as imperative calls.
- Always back up existing target to `target.bak` before replacing.

Windows Terminal `settings.json` path is resolved dynamically via `Get-AppxPackage -Name *WindowsTerminal*`.
**Warning:** Windows Terminal must be closed when symlinking its settings — it overwrites the file on exit.

---

## WSL2 Integration

Two-phase setup:

### Windows-side (`scripts/Install-WSL.ps1`)
1. Enable `VirtualMachinePlatform` + `Microsoft-Windows-Subsystem-Linux` features (requires elevation + reboot)
2. `wsl --set-default-version 2`
3. Install distro via WinGet: `Canonical.Ubuntu.2404`
4. Copy (not symlink) `config/.wslconfig` to `$HOME\.wslconfig`
5. Invoke `wsl/bootstrap-wsl.sh` inside the distro

**Reboot resume**: write a registry key before reboot (`HKCU:\Software\YourDotfiles\ResumePhase`) and a run-once entry to continue setup after login.

### Linux-side (`wsl/bootstrap-wsl.sh`)
1. Install packages from `packages-apt.txt`
2. Symlink dotfiles from `wsl/dotfiles-wsl/` into WSL `$HOME`
3. Copy `config/wsl.conf` to `/etc/wsl.conf`
4. Install language tooling (nvm, pyenv, etc.)

### Key config defaults

`.wslconfig`:
```ini
[wsl2]
memory=8GB
processors=4
swap=2GB
localhostForwarding=true

[experimental]
sparseVhd=true
autoMemoryReclaim=gradual
```

`wsl.conf`:
```ini
[automount]
enabled=true
options="metadata,uid=1000,gid=1000,umask=22"

[interop]
appendWindowsPath=false

[boot]
systemd=true
```

`appendWindowsPath=false` keeps WSL PATH clean. Without it, `which python` may resolve to a Windows binary.

---

## SSH Agent

Use Windows native OpenSSH (`ssh-agent` Windows service), not WSL or Git for Windows agent.

`Set-SshAgent.ps1`:
1. Enable `OpenSSH.Client` optional feature
2. Set `ssh-agent` service to `Automatic` + start it
3. Add `ssh-add` call to profile (guarded by `ssh-add -l` check)
4. Configure WSL → Windows agent forwarding via `npiperelay` (document in `MANUAL_STEPS.md` if manual)

---

## Implementation Order

Build and test each file independently before wiring into `setup.ps1`:

| Step | File | Notes |
|---|---|---|
| 1 | `config/packages.json` | Pure data |
| 2 | `config/scoop-packages.json` | Pure data |
| 3 | `powershell/modules.json` | Pure data |
| 4 | `scripts/Install-Packages.ps1` | Test in isolation |
| 5 | `scripts/Install-PSModules.ps1` | Test independently |
| 6 | `scripts/Set-Symlinks.ps1` | Use `-WhatIf` before running |
| 7 | `powershell/profile.ps1` + sub-files | Dot-source manually to test |
| 8 | `config/settings.json` | Export from configured Windows Terminal |
| 9 | `scripts/Set-WindowsSettings.ps1` | Test on VM first |
| 10 | `wsl/bootstrap-wsl.sh` | Test in throwaway WSL distro |
| 11 | `scripts/Install-WSL.ps1` | Most destructive — test last |
| 12 | `setup.ps1` | Wire phases once each works |
| 13 | `bootstrap.ps1` | Test on a fresh VM |

---

## Key Pitfalls

| Pitfall | Mitigation |
|---|---|
| `$PROFILE` path differs by PS host | Use `CurrentUserAllHosts`; source via stub |
| Symlinks need Developer Mode or admin | Enable via registry in `Set-WindowsSettings` first |
| WinGet exits `0` AND `-1978335189` for "already installed" | Handle both exit codes as success |
| Windows Terminal overwrites symlinked `settings.json` on close | Warn in script; document in `MANUAL_STEPS.md` |
| WSL feature enable requires reboot | Registry resume key + run-once entry |
| PATH changes in PS don't persist without `SetEnvironmentVariable` | Never use `$env:PATH +=` for permanent changes |
| `Documents\` may be OneDrive-redirected | Keep dotfiles in `$HOME\.dotfiles\`, not `Documents` |
| Scoop and WinGet can conflict on same tool PATH order | Install WinGet first, Scoop second; Scoop shims take precedence |
| `appendWindowsPath=true` in WSL causes wrong binary resolution | Default to `false`; document trade-off |

---

## Mental Model

> **`config/` is your source of truth. `scripts/` is your actuator. `setup.ps1` is your `make`. `bootstrap.ps1` is your install URL.**

Every script reads from config files and tests current state before acting. Nothing is hardcoded in scripts that belongs in data.
