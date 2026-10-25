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
-- 今いるペインのタブだけ枠の色（PaneWinbar）、他は沈んだ色（PaneWinbarNC）。色は lua/plugins/colorscheme.lua。
-- Neovim は境界線をペインごとに塗り分けられないので、「今どのペインか」はこのタブで示す。
local winbar = vim.api.nvim_create_augroup("pane_winbar", { clear = true })

local function set_winbar(win, active)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype == "" and name ~= "" then
    -- Obsidian vault の中のファイルは、今いるペインかどうかに関わらず紫（lua/config/vault.lua）
    local hl = require("config.vault").contains(name) and "VaultWinbar" or active and "PaneWinbar" or "PaneWinbarNC"
    vim.wo[win].winbar = "%#" .. hl .. "# %f %m %#" .. (active and "WinBar" or "WinBarNC") .. "#"
  else
    vim.wo[win].winbar = ""
  end
end

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
  group = winbar,
  callback = function()
    set_winbar(vim.api.nvim_get_current_win(), true)
  end,
})

vim.api.nvim_create_autocmd("WinLeave", {
  group = winbar,
  callback = function()
    set_winbar(vim.api.nvim_get_current_win(), false)
  end,
})

----------------------------------------------------
-- カーソルの十字（行＋列のハイライト）
----------------------------------------------------
-- 今いる行（cursorline）と今いる桁（cursorcolumn）を同じ色で塗って、分割した画面でも
-- 「どのファイルの・どこにいるか」が一目で分かるようにする。
--   * 色は lua/plugins/colorscheme.lua（CursorLine・CursorLineNr）。行番号の桁も同じ地にしてある。
--   * 塗るのはアクティブなウィンドウだけ＝十字は常に 1 つ。
--   * 対象は通常のファイルのみ。ファイルツリー・ヘルプ・ターミナル・フロートでは
--     cursorline を触らない（neo-tree などは自前の cursorline で選択位置を出しているため）。
local cross = vim.api.nvim_create_augroup("cursor_cross", { clear = true })

-- 通常のファイルを表示しているウィンドウか（winbar の判定と同じ条件）
local function is_file_win(win)
  if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function show_cross(win, on)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if is_file_win(win) then
    vim.wo[win].cursorline = on
    vim.wo[win].cursorcolumn = on
  else
    -- ファイル以外の窓（ファイルツリー・ターミナル・フロート）。新しい窓は開いた元の窓の
    -- ウィンドウ設定を引き継ぐので、縦列だけはここで明示的に消す。cursorline は触らない。
    vim.wo[win].cursorcolumn = false
  end
end

vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
  group = cross,
  callback = function()
    show_cross(vim.api.nvim_get_current_win(), true)
  end,
})

vim.api.nvim_create_autocmd("WinLeave", {
  group = cross,
  callback = function()
    show_cross(vim.api.nvim_get_current_win(), false)
  end,
})

-- 起動直後の 1 枚目には WinEnter が来ないので、ここで 1 回だけ点ける。
show_cross(vim.api.nvim_get_current_win(), true)

----------------------------------------------------
-- INSERT 以外では IME を OFF にする
----------------------------------------------------
-- 中身と理由は lua/config/ime.lua（Windows の nvim でだけ効く・他では何もしない）
require("config.ime").setup()

----------------------------------------------------
-- Obsidian vault の中に居る時は紫で示す
----------------------------------------------------
-- 中身と理由は lua/config/vault.lua（winbar の色は上の pane_winbar が選ぶ）
require("config.vault").setup()
