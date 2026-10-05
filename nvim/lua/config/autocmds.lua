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

----------------------------------------------------
-- カーソルの十字（行＋列のハイライト）
----------------------------------------------------
-- 今いる行（cursorline）と今いる桁（cursorcolumn）を同じ色で塗って、分割した画面でも
-- 「どのファイルの・どこにいるか」が一目で分かるようにする。
--   * 色は tokyonight の既定（moon の bg_highlight #2f334d）より強い #3b4261。
--     colorscheme.lua で背景を透過させている＝地が WezTerm の黒なので、既定だとほぼ見えない。
--   * 塗るのはアクティブなウィンドウだけ＝十字は常に 1 つ。
--   * 対象は通常のファイルのみ。ファイルツリー・ヘルプ・ターミナル・フロートでは
--     cursorline を触らない（neo-tree などは自前の cursorline で選択位置を出しているため）。
local cross = vim.api.nvim_create_augroup("cursor_cross", { clear = true })

local CROSS_BG = "#3b4261"

local function paint()
  vim.api.nvim_set_hl(0, "CursorLine", { bg = CROSS_BG })
  vim.api.nvim_set_hl(0, "CursorColumn", { bg = CROSS_BG })
  -- 行番号も同じ背景にして、番号の桁からハイライトが途切れないようにする。
  -- 文字色はテーマのまま（tokyonight ではオレンジ）＋太字。
  local nr = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
  nr.bg = CROSS_BG
  nr.bold = true
  vim.api.nvim_set_hl(0, "CursorLineNr", nr)
end

-- ここで直に paint() を呼んでも効かない。`nvim <file>` で起動すると LazyVim は
-- このファイルを colorscheme より先に読み込み（argc>0 の経路）、テーマが後から塗り潰す。
-- その時の ColorScheme イベントも lazy.nvim が起動中に eventignore で潰すので拾えない
-- （2026-10-05 に実測）。起動処理が終わってから＝vim.schedule で 1 回塗る。
-- テーマを切り替えた時は ColorScheme で塗り直す。
vim.api.nvim_create_autocmd("ColorScheme", { group = cross, callback = paint })
vim.schedule(paint)

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
