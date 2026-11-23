# Neovim on Windows

This is the previous personal LazyVim configuration, now owned by this Windows
repository instead of a submodule. The upstream starter's license is retained
in `LICENSE`.

The plugin lockfile, theme, keymaps, language extras, disabled cursor animation,
and disabled background update checks are retained. Windows-specific changes:

- Shell commands use PowerShell 7 without loading its interactive profile.
- Mason manages language servers; Nix/macOS overrides and the Nix language
  server have been removed.
- Python environments are discovered under `venv`, `.venv`, or `.virtualenv`
  using `Scripts\python.exe` / `Scripts\pylsp.exe`.
- Gitsigns detects the installed Git version instead of assuming one machine's
  version.

Open `nvim` to let LazyVim download plugins. `:Lazy restore` uses `lazy-lock.json`;
`:Lazy check` checks for updates manually.

Neovim 0.12+ is required by the retained Roslyn plugin; a Nerd Font in your
terminal is recommended. Language extras still need their own runtimes (for
example .NET, Go, Node.js, or Python). Run `mise install` after dotfiles setup to
install the configured Rust, Go, and Node.js defaults, then launch Neovim from a
mise-activated PowerShell 7 session. .NET and Python are not included. Mason still manages
language servers. Use `:checkhealth` and `:Mason` to inspect language-tool
requirements.

C# uses Roslyn by default. OmniSharp from `lang.dotnet` stays disabled, and Mason
automatically installs `roslyn` from the configured supplemental registry.
Keep a .NET SDK available on PATH. After the initial installation finishes,
restart Neovim, open a `.cs` file within a project or solution, and use
`:LspInfo` to check attachment.
A C compiler is not needed to run Roslyn.

Treesitter parser builds need a C compiler and the tree-sitter CLI. For MSVC,
run `setup.ps1 -BuildTools` and launch Neovim from **Developer PowerShell for
VS 2022**, so `cl.exe` and the Windows SDK are available. Install the tree-sitter
CLI using Mason (`:MasonInstall tree-sitter-cli`). Existing working compilers
can be used instead; the large Visual Studio workload is not a default dependency.
