# WhereZenZoo

Minimal dotfiles for **Windows 11 + PowerShell 7**. One repository owns the
PowerShell, Neovim/LazyVim, Git, mise, and Herdr configs. No submodules, Make,
PowerShell 5 compatibility layer, or automatic OneDrive/module relocation.

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
Scripted calls can explicitly enable or disable that switch with
`-BuildTools:$true` or `-BuildTools:$false`.

## Tools

Edit the small list in `config\packages.json` to change what is installed:

| Default | WinGet ID |
| --- | --- |
| Git | `Git.Git` |
| Neovim | `Neovim.Neovim` |
| fd | `sharkdp.fd` |
| fzf | `junegunn.fzf` |
| ripgrep | `BurntSushi.ripgrep.MSVC` |
| lazygit | `JesseDuffield.lazygit` |
| zoxide | `ajeetdsouza.zoxide` |
| mise | `jdx.mise` |
| GitHub CLI | `GitHub.cli` |
| GitHub Copilot CLI | `GitHub.Copilot` |

Existing applications on PATH or packages known to WinGet are skipped, not
upgraded. Setup stops on package-manager errors; fix the error and rerun.
Visual Studio 2022 C++ Build Tools is **optional** with `-BuildTools`, which
installs the C++ workload and recommended Windows SDK. It can require a reboot.

The retained LazyVim language extras need their own language runtimes and parser
build tools; see [`nvim\README.md`](nvim/README.md). mise manages the Rust, Go,
and Node.js defaults below; .NET and Python are not included.

## Programming languages with mise

[`config\mise\config.toml`](config/mise/config.toml) selects the global defaults:

| Language | Version request |
| --- | --- |
| Rust | `stable` |
| Go | `latest` stable release |
| Node.js | `22` (latest available 22.x release) |

Setup installs mise and connects its configuration, but does **not** download or
upgrade language toolchains. After setup, open a new PowerShell 7 terminal and run:

```powershell
mise install
mise ls --current
rustc --version
cargo --version
go version
node --version
```

The profile activates mise when its executable is available, so selected tools
are on PATH and project configs take effect as you change directories. Shell
startup never installs or upgrades tools. Initialization failures produce a
warning without preventing aliases or zoxide from loading.

Command-not-found auto-installation is disabled, so checking a missing command
with `Get-Command` does not install its toolchain. Use `mise install` explicitly.
After changing this setting, open a new PowerShell session so any previously
registered auto-install hook is no longer present.

Run `mise upgrade` explicitly to update within these requests; Node.js stays on
22.x. A project's `mise.toml` or `.tool-versions` overrides the global defaults.
From a project directory, use `mise use go@<version>`, `mise use node@<version>`,
or `mise use rust@<version>` to select and install its version. For example,
`mise use node@22` follows 22.x; use a full version to pin an exact release.
Run `mise install` after entering an existing project with missing tool versions.

Rust uses rustup underneath. Reading project `rust-toolchain.toml` files is
enabled so the global `stable` default does not override a project's toolchain.
MSVC Rust builds need the C++ workload and Windows SDK; install them with
`setup.ps1 -BuildTools` if they are missing. mise does not replace those build
dependencies. See the official [Rust](https://mise.jdx.dev/lang/rust.html) and
[Go](https://mise.jdx.dev/lang/go.html) guides for language-specific behavior.

`mise use -g` edits the linked, tracked global config. Review those changes
before committing, and keep credentials and machine-specific secrets out of it.
Toolchains, rustup/Cargo state, and mise caches stay outside the repository.
The existing PowerShell scripts still own dotfile deployment and rollback;
`mise dotfiles` and `mise bootstrap` are not used.

## Live configs

| Repository source | Installed location | Mechanism |
| --- | --- | --- |
| `powershell\profile.ps1` | `$PROFILE.CurrentUserAllHosts` | Small dot-sourcing loader |
| `nvim\` | `%LOCALAPPDATA%\nvim` | Directory junction |
| `git\` | `%USERPROFILE%\.config\git` | Directory junction |
| `config\mise\` | `%USERPROFILE%\.config\mise` | Directory junction |
| `herdr\config.toml` | `HERDR_CONFIG_PATH` | Repo-relative override set by the PowerShell profile |

Edits in the repo are immediately reflected in linked configs. Reload PowerShell
or Neovim as appropriate. Keep the clone in place while it is in use. Before
moving it, run uninstall from the old location, move it, and rerun setup.

The PowerShell profile loads repo-relative aliases (`v`, `ll`, `copilot`) and
caches zoxide initialization until its executable changes. `copilot` uses
`agency copilot` when Agency is on PATH, otherwise the standalone GitHub Copilot
CLI. Agency itself is not installed by this repo.

The profile points Herdr at this clone's `herdr\config.toml`, replacing any
inherited `HERDR_CONFIG_PATH`. Launch Herdr from PowerShell 7 after loading the
profile; edits in Herdr's settings UI are saved directly to the repo file.
Logs, sockets, plugins, and session state stay in `%APPDATA%\herdr`, outside Git.
This uses Herdr's supported config-path override, not a file symlink requiring
Developer Mode or a junction that would pull runtime data into the repository.
Herdr itself is not installed by this repo.
An existing `%APPDATA%\herdr\config.toml` is left untouched as a fallback for
launches outside the managed PowerShell profile.

After editing the config, run `herdr config check` and
`herdr server reload-config`. Reopen Herdr for client-side settings to take
effect. Setup installs the profile loader as usual; no persistent Windows
environment variable is changed. Uninstall restores the previous profile, so
fresh PowerShell terminals stop setting this override. Already-open shells and
Herdr panes keep inherited environment values until restarted.

The Git identity is retained. Commit signing is **opt-in**, configured in the
ignored `git\config.local` after adding a signing key. Existing
`%USERPROFILE%\.gitconfig` settings remain untouched and take precedence.
See [`git\README.md`](git/README.md).

## Backups and rollback

Conflicting configs are backed up beside their destination as
`<path>.wherezenzoo-backup` before replacement. Old linked directories are copied
into real backup directories, so rollback does not depend on the old source.
An old linked profile is backed up as a loader to its original source
so script-relative imports still work; keep that original source in place.
If an existing link's target is missing, setup warns and backs up the broken
link itself instead; uninstall restores that link, not its missing contents.
Neovim is always installed from this repo's `nvim\` directory, never a submodule.
Correct configs are skipped on repeat runs; the original backup is
never overwritten. If a config was subsequently replaced and a backup already
exists, setup stops and asks you to move the changed config aside.

Uninstall removes only the matching junctions/profile loader and restores those
backups. It stops if a managed path was edited or retargeted. It **never**
uninstalls applications, purges Neovim data, removes the clone, or moves/deletes
PowerShell modules. There is no remote uninstall one-liner or `-Purge` mode.
Use `winget uninstall --id <package-id> --exact` to remove an application yourself.

An existing `%USERPROFILE%\.config\mise` directory is backed up in full, not
merged into the tracked defaults. Review its backup for settings you want to
retain. Uninstall restores that directory and leaves downloaded language
toolchains, Cargo data, and mise caches intact.

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
