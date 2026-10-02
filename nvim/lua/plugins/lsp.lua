-- Adapted from the previous dotfiles config for Windows virtual environments.
local function venv_executable(root, executable)
  for _, directory in ipairs({ "venv", ".venv", ".virtualenv" }) do
    local path = vim.fs.joinpath(root, directory, "Scripts", executable)
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        lua_ls = {},
        ts_ls = {},
        html = {},
        cssls = {},
        jsonls = {},
        eslint = {},
        pyright = {
          before_init = function(_, config)
            local python = venv_executable(config.root_dir or vim.fn.getcwd(), "python.exe")
            if python then
              config.settings = config.settings or {}
              config.settings.python = config.settings.python or {}
              config.settings.python.pythonPath = python
            end
          end,
          settings = {
            python = {
              analysis = {
                autoImportCompletions = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
              },
            },
          },
        },
        rust_analyzer = {},
        gopls = {
          settings = {
            gopls = {
              formatting = {
                ["local"] = "github.com/anzx/fabric-entitlements",
              },
              gofumpt = true,
            },
          },
        },
        omnisharp = { enabled = false },
        pylsp = {
          on_new_config = function(config, root_dir)
            local pylsp = venv_executable(root_dir, "pylsp.exe")
            if pylsp then
              config.cmd = { pylsp }
            end
          end,
          settings = {
            pylsp = {
              plugins = {
                ruff = {
                  enabled = true,
                  formatEnabled = true,
                  lineLength = 88,
                  select = { "F", "I" },
                  fixAll = true,
                },
                pycodestyle = { enabled = false },
                mccabe = { enabled = false },
                pyflakes = { enabled = false },
                autopep8 = { enabled = false },
                yapf = { enabled = false },
                isort = { enabled = false },
              },
            },
          },
        },
      },
    },
  },
}
