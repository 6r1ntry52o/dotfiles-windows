-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

----------------------------------------------------
-- 今開いているファイルを Windows の既定アプリで開く
----------------------------------------------------
-- <leader>fo … 拡張子の関連付けに従って開く（.xlsx→Excel・.png→画像ビューア・.md→Obsidian 等）。
-- nvim 標準の gx はカーソル下のリンク／パスが対象で、バッファ自身は開けないので別に持つ。
-- 中身は vim.ui.open＝Windows では `cmd.exe /c start "" <path>`（＝エクスプローラでダブルクリックと同じ）。
-- 既定アプリで開くだけなので nvim 側のバッファには触らない（保存も読み直しもしない）。
vim.keymap.set("n", "<leader>fo", function()
  local path = vim.api.nvim_buf_get_name(0)
  -- buftype ~= "" はターミナル・ファイルツリー・ヘルプなど実ファイルでないバッファ
  if path == "" or vim.bo.buftype ~= "" then
    vim.notify("ファイルのバッファではありません", vim.log.levels.WARN)
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

-- <leader>fO … そのファイルをエクスプローラで選択状態にして開く（置き場所を見たい時）。
-- 親フォルダを開くだけなら vim.ui.open(dirname) でも足りるが、/select で当該ファイルに当たりが付く。
vim.keymap.set("n", "<leader>fO", function()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or vim.bo.buftype ~= "" then
    vim.notify("ファイルのバッファではありません", vim.log.levels.WARN)
    return
  end
  -- explorer.exe /select は区切りが \ でないと無視されて「ドキュメント」が開く
  vim.system({ "explorer.exe", "/select," .. path:gsub("/", "\\") }, { detach = true })
end, { desc = "Reveal in Explorer" })
