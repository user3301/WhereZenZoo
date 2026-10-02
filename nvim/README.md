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

Neovim 0.11.2+ and a Nerd Font in your terminal are recommended for the retained
LazyVim setup. Language extras still need their own runtimes (for example .NET,
Go, Node.js, or Python); bootstrap deliberately does not install those SDKs.
Use `:checkhealth` and `:Mason` to inspect language-tool requirements.

Treesitter parser builds need a C compiler and the tree-sitter CLI. For MSVC,
run `setup.ps1 -BuildTools` and launch Neovim from **Developer PowerShell for
VS 2022**, so `cl.exe` and the Windows SDK are available. Install the tree-sitter
CLI using Mason (`:MasonInstall tree-sitter-cli`). Existing working compilers
can be used instead; the large Visual Studio workload is not a default dependency.
