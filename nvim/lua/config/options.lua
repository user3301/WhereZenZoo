-- Windows-specific adaptation of the previous dotfiles options.

local git_cmd_dir = "C:\\Program Files\\Git\\cmd"
local git_bin_dir = "C:\\Program Files\\Git\\mingw64\\bin"

-- Avoid Git's extra launcher process without putting all its bundled tools first on PATH.
if vim.uv.fs_stat(git_bin_dir .. "\\git.exe") then
  local path_parts = vim.split(vim.env.PATH or "", ";", { plain = true })
  for index, path_part in ipairs(path_parts) do
    if path_part:gsub("[\\/]+$", ""):lower() == git_cmd_dir:lower() then
      path_parts[index] = git_bin_dir
      vim.env.PATH = table.concat(path_parts, ";")
      break
    end
  end
end

local opts = vim.opt

opts.shell = "pwsh"
opts.shellcmdflag = "-NoLogo -NoProfile -Command "
  .. "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new(); "
  .. "$PSDefaultParameterValues['Out-File:Encoding']='utf8';"
opts.shellredir = "2>&1 | %%{ \"$_\" } | Out-File %s; exit $LastExitCode"
opts.shellpipe = "2>&1 | %%{ \"$_\" } | Tee-Object %s; exit $LastExitCode"
opts.shellquote = ""
opts.shellxquote = ""
opts.relativenumber = false
opts.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opts.foldmethod = "expr"
