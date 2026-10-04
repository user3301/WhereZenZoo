local root = assert(arg[1], "Repository path is required")

for _, file in ipairs(vim.fn.globpath(vim.fs.joinpath(root, "nvim"), "**/*.lua", false, true)) do
  assert(loadfile(file))
end

local servers = dofile(vim.fs.joinpath(root, "nvim", "lua", "plugins", "lsp.lua"))[1].opts.servers
assert(servers.nil_ls == nil, "The Windows config must not start the Nix language server")
assert(servers.omnisharp.enabled == false, "Roslyn replaces OmniSharp")

local original_executable = vim.fn.executable
local python = vim.fs.joinpath(root, ".venv", "Scripts", "python.exe")
local pylsp = vim.fs.joinpath(root, ".venv", "Scripts", "pylsp.exe")
vim.fn.executable = function(path)
  return (path == python or path == pylsp) and 1 or 0
end
local python_config = { root_dir = root }
servers.pyright.before_init(nil, python_config)
assert(python_config.settings.python.pythonPath == python, "Pyright must use the Windows virtualenv")
local pylsp_config = {}
servers.pylsp.on_new_config(pylsp_config, root)
assert(pylsp_config.cmd[1] == pylsp, "pylsp must use the Windows virtualenv")
vim.fn.executable = original_executable

dofile(vim.fs.joinpath(root, "nvim", "lua", "config", "options.lua"))
assert(vim.o.shell == "pwsh", "Neovim must use PowerShell 7")
local result = vim.fn.system("'WhereZenZoo shell test'")
assert(vim.v.shell_error == 0 and result:find("WhereZenZoo shell test", 1, true), result)
vim.fn.system("pwsh -NoProfile -Command 'exit 7'")
assert(vim.v.shell_error ~= 0, "Neovim must report native command failures")
vim.fn.system("exit 7")
assert(vim.v.shell_error == 7, "Neovim must preserve explicit PowerShell exit codes")
print("Neovim syntax, Windows virtualenvs, and PowerShell shell checks passed")
