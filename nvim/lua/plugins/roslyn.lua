-- Windows uses Mason's Roslyn installation and Neovim's file watcher.
return {
  "seblyng/roslyn.nvim",
  ft = "cs",
  opts = {
    filewatching = "auto",
  },
  init = function()
    vim.lsp.config("roslyn", {
      capabilities = {
        workspace = {
          didChangeWatchedFiles = {
            dynamicRegistration = true,
          },
        },
      },
    })
  end,
}
