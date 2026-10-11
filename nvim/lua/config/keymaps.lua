-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

----------------------------------------------------
-- ターミナルは下ではなく右のペインに開く
----------------------------------------------------
-- LazyVim 既定の同じキーを上書きする（既定は position = "bottom"）。
-- snacks の opts.terminal.win に書かないのは、そこは Snacks.lazygit など cmd 付きの
-- ターミナル（フロート）にも効いてしまうため。シェルを開くキーだけに絞る。
-- <c-/> は <leader>ft と同じターミナルを掴む（id は cmd・cwd・count で決まり、位置は
-- 最初に開いた時のものが残る）ので、揃えておかないと開いたキー次第で位置が変わる。
local term_win = { position = "right" }

vim.keymap.set("n", "<leader>fT", function()
  Snacks.terminal(nil, { win = term_win })
end, { desc = "Terminal (cwd)" })
vim.keymap.set("n", "<leader>ft", function()
  Snacks.terminal(nil, { cwd = LazyVim.root(), win = term_win })
end, { desc = "Terminal (Root Dir)" })
vim.keymap.set({ "n", "t" }, "<c-/>", function()
  Snacks.terminal.focus(nil, { cwd = LazyVim.root(), win = term_win })
end, { desc = "Terminal (Root Dir)" })
vim.keymap.set({ "n", "t" }, "<c-_>", function()
  Snacks.terminal.focus(nil, { cwd = LazyVim.root(), win = term_win })
end, { desc = "which_key_ignore" })

----------------------------------------------------
-- 今のファイルを Windows 側に渡す（開く・パスを取る）
----------------------------------------------------
-- ここはカーソルがファイルの中に居る時の口。snacks explorer でカーソルが当たって
-- いるファイルに対しては、同じキーを lua/plugins/snacks.lua が登録している
-- （どちらも実装は lua/config/winpath.lua）。

-- 実ファイルのバッファなら、そのパスを返す。
-- buftype ~= "" はターミナル・ファイルツリー・ヘルプなど実ファイルでないバッファ。
local function cur_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or vim.bo.buftype ~= "" then
    vim.notify("ファイルのバッファではありません", vim.log.levels.WARN)
    return
  end
  return path
end

-- <leader>fo … 拡張子の関連付けに従って開く（.xlsx→Excel・.png→画像ビューア・.md→Obsidian 等）。
-- nvim 標準の gx はカーソル下のリンク／パスが対象で、バッファ自身は開けないので別に持つ。
-- 中身は vim.ui.open＝Windows では `cmd.exe /c start "" <path>`（＝エクスプローラでダブルクリックと同じ）。
-- 既定アプリで開くだけなので nvim 側のバッファには触らない（保存も読み直しもしない）。
vim.keymap.set("n", "<leader>fo", function()
  local path = cur_file()
  if not path then
    return
  end
  -- 既定アプリはディスク上の中身を読む＝新規バッファは開く先が無い
  if not vim.uv.fs_stat(path) then
    vim.notify("まだ保存されていません（:w のあとで）", vim.log.levels.ERROR)
    return
  end
  if vim.bo.modified then
    vim.notify("未保存の変更は反映されません（保存前の中身が開きます）", vim.log.levels.WARN)
  end
  -- vault（core）の中のノートは既定アプリではなく Obsidian で開く。
  -- vim.b.obsidian_buffer は obsidian.nvim が vault 内の md に立てる印なので、
  -- vault の外の md（リポの README 等）はそのまま下の既定アプリに落ちる。
  if vim.b.obsidian_buffer then
    vim.cmd "Obsidian open"
    return
  end
  local _, err = vim.ui.open(path)
  if err then
    vim.notify(err, vim.log.levels.ERROR)
  end
end, { desc = "Open in default app / Obsidian" })

-- <leader>fw … そのファイルをエクスプローラで選択状態にして開く（置き場所を見たい時）。
-- w＝Windows。3 つは渡すものが違う: fo＝中身をアプリに、fw＝場所をエクスプローラに、
-- fy＝パスの文字列をクリップボードに。大文字を使わないのは、LazyVim の <leader>f では
-- 大文字が「同じ機能の cwd 版」（fe/fE・ff/fF・fr/fR）を意味するため。
vim.keymap.set("n", "<leader>fw", function()
  local path = cur_file()
  if path then
    require("config.winpath").reveal(path)
  end
end, { desc = "Reveal in Explorer" })

-- <leader>fy … そのファイルの絶対パスを \ 区切りでクリップボードへ。
-- fs_stat は見ない: パスは保存前でも確定していて、貼る相手（チャット・チケット）に
-- 実体は要らない。reveal と違ってディスクを触らないので弾く理由が無い。
vim.keymap.set("n", "<leader>fy", function()
  local path = cur_file()
  if path then
    require("config.winpath").copy(path)
  end
end, { desc = "Copy absolute path" })
