# WhereZenZoo

Minimal dotfiles for **Windows 11 + PowerShell 7**. One repository owns the
PowerShell, Neovim/LazyVim, and Git configs. No submodules, Make, PowerShell 5
compatibility layer, or automatic OneDrive/module relocation.

## Bootstrap

Open **PowerShell 7** (`pwsh`) in Windows Terminal and run:

```powershell
irm https://raw.githubusercontent.com/user3301/WhereZenZoo/main/install.ps1 | iex
```

Requires **WinGet** (Microsoft Store's **App Installer**) and internet access.
Run as your normal user; individual package installers may request elevation.
Developer Mode is **not** required. Review `install.ps1` before executing
downloaded code. This URL uses the version published on `main`, not uncommitted
changes in a local clone.

The installer installs Git if needed, clones into `$HOME\dotfiles`, installs the
default tools, and connects your configs. A repeat run fast-forwards a clean
`main` checkout. It refuses a different repository, local edits, another branch,
or a failed update instead of overwriting work or running stale setup.

Profiles must be allowed by your execution policy. If local scripts are blocked
and your organization permits it, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Setup checks the persistent policy (not the installer's temporary process
bypass) and stops if it would block the unsigned profile. It does not weaken
persistent execution policies or bypass Group Policy. Open a new terminal after
setup to load the profile and updated PATH.

## Local commands

From this clone:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1                # tools + configs
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -SkipPackages  # configs only
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -PackagesOnly  # tools only
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -BuildTools    # also install C++ tools
pwsh -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1           # restore configs only
```

Local setup uses your current files without fetching or requiring a clean
worktree. For a different clone location, download `install.ps1`, inspect it, and
run it with `-Destination 'C:\path\to\dotfiles'`. `-BuildTools` is also supported.

## Tools

Edit the small list in `config\packages.json` to change what is installed:

| Default | WinGet ID |
| --- | --- |
| Git | `Git.Git` |
| Neovim | `Neovim.Neovim` |
| fd | `sharkdp.fd` |
| ripgrep | `BurntSushi.ripgrep.MSVC` |
| lazygit | `JesseDuffield.lazygit` |
| zoxide | `ajeetdsouza.zoxide` |
| GitHub CLI | `GitHub.cli` |
| GitHub Copilot CLI | `GitHub.Copilot` |

Existing applications on PATH or packages known to WinGet are skipped, not
upgraded. Setup stops on package-manager errors; fix the error and rerun.
Visual Studio 2022 C++ Build Tools is **optional** with `-BuildTools`, which
installs the C++ workload and recommended Windows SDK. It can require a reboot.

The retained LazyVim language extras need their own language runtimes and parser
build tools; see [`nvim\README.md`](nvim/README.md). They are not all installed by
this minimal bootstrap.

## Live configs

| Repository source | Installed location | Mechanism |
| --- | --- | --- |
| `powershell\profile.ps1` | `$PROFILE.CurrentUserAllHosts` | Small dot-sourcing loader |
| `nvim\` | `%LOCALAPPDATA%\nvim` | Directory junction |
| `git\` | `%USERPROFILE%\.config\git` | Directory junction |

Edits in the repo are immediately reflected in linked configs. Reload PowerShell
or Neovim as appropriate. Keep the clone in place while it is in use. Before
moving it, run uninstall from the old location, move it, and rerun setup.

The PowerShell profile loads repo-relative aliases (`v`, `ll`, `copilot`) and
caches zoxide initialization until its executable changes. `copilot` uses
`agency copilot` when Agency is on PATH, otherwise the standalone GitHub Copilot
CLI. Agency itself is not installed by this repo.

The Git identity is retained. Commit signing is **opt-in**, configured in the
ignored `git\config.local` after adding a signing key. Existing
`%USERPROFILE%\.gitconfig` settings remain untouched and take precedence.
See [`git\README.md`](git/README.md).

## Backups and rollback

Conflicting configs are backed up beside their destination as
`<path>.wherezenzoo-backup` before replacement. Old linked directories are copied
into real backup directories, so rollback does not depend on the removed
submodule. An old linked profile is backed up as a loader to its original source
so script-relative imports still work; keep that original source in place.
Correct configs are skipped on repeat runs; the original backup is
never overwritten. If a config was subsequently replaced and a backup already
exists, setup stops and asks you to move the changed config aside.

Uninstall removes only the matching junctions/profile loader and restores those
backups. It stops if a managed path was edited or retargeted. It **never**
uninstalls applications, purges Neovim data, removes the clone, or moves/deletes
PowerShell modules. There is no remote uninstall one-liner or `-Purge` mode.
Use `winget uninstall --id <package-id> --exact` to remove an application yourself.

The previous `~\powershell` link, host-specific profiles, old install records,
and any pre-existing OneDrive redirection are not managed by this version.
The new loader uses PowerShell 7's all-hosts profile; remove an obsolete
host-specific loader yourself if it loads the same profile a second time.

## Repository checks

Pester 5+ is a development-only dependency; bootstrap does not install modules.
If missing, install it with `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser`.

```powershell
pwsh -NoProfile -File .\check.ps1
```

This parses PowerShell/JSON and runs isolated tests for bootstrap failures,
package detection, live configs, backup/rollback, and profile startup. Tests do
not install packages or update your actual configs. When Neovim is available,
it also checks Lua syntax, Windows virtualenv detection, and the PowerShell shell
without downloading plugins.
