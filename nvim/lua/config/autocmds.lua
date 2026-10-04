-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- 分割した各ペインの上端に、そのペインのファイル名タブ(winbar)を出す。
-- 通常のファイルだけ対象（ファイルツリー・ヘルプ・ターミナル・フロートは除外）。
vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = vim.api.nvim_create_augroup("pane_winbar", { clear = true }),
  callback = function(ev)
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return
    end
    if vim.bo[ev.buf].buftype == "" and vim.api.nvim_buf_get_name(ev.buf) ~= "" then
      vim.wo[win].winbar = "%#TabLineSel# %f %m %#WinBar#"
    else
      vim.wo[win].winbar = ""
    end
  end,
})
