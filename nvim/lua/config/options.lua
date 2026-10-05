-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Use PowerShell 7 for :terminal, :! and Snacks.terminal (<leader>ft / <leader>fT / <c-/>)
LazyVim.terminal.setup("pwsh")

----------------------------------------------------
-- 文字コード
----------------------------------------------------
-- 読み込み時の判定順。既定は ucs-bom,utf-8,default,latin1 で、latin1 は
-- どんなバイト列でも「成功」するため、CP932（Shift_JIS）のファイルが必ず化ける。
-- cp932 を latin1 の前に入れて、先に判定させる。
--   ucs-bom … BOM 付き（UTF-8 BOM・UTF-16LE/BE）を BOM で見分ける
--   utf-8   … BOM なし UTF-8（不正バイトがあれば次へ落ちる）
--   cp932   … Windows の Shift_JIS。社内のソース・CSV・古いログがこれ
--   latin1  … 最後の受け皿（ここに来たら判定失敗＝化ける）
-- euc-jp と iso-2022-jp は入れない: euc-jp は cp932 とバイト範囲が重なり誤判定を
-- 増やすだけで、iso-2022-jp は 7bit なので utf-8 の段階で通ってしまい効かない。
-- 個別のファイルは :EncOpen euc-jp のように指定して読み直す。
vim.opt.fileencodings = { "ucs-bom", "utf-8", "cp932", "latin1" }

-- 保存は読み込んだ時の文字コードを維持する（Neovim の既定の挙動）。
-- CP932 で開いたファイルは CP932 のまま書き戻る＝勝手に変換しない。
-- UTF-8 に変えたい時だけ :EncToUtf8 を使う。

-- :EncOpen <enc> … 今のファイルを指定の文字コードで読み直す（判定を間違えた時）
vim.api.nvim_create_user_command("EncOpen", function(a)
  if vim.bo.modified then
    vim.notify("未保存の変更があります（読み直すと失われます）", vim.log.levels.ERROR)
    return
  end
  vim.cmd("edit! ++enc=" .. a.args)
end, {
  nargs = 1,
  complete = function()
    return { "utf-8", "cp932", "euc-jp", "iso-2022-jp", "utf-16le", "utf-16", "latin1" }
  end,
  desc = "今のファイルを指定の文字コードで読み直す",
})

-- :EncToUtf8 … 今のファイルを UTF-8（BOM なし）にして保存する
vim.api.nvim_create_user_command("EncToUtf8", function()
  vim.bo.fileencoding = "utf-8"
  vim.bo.bomb = false
  vim.cmd.write()
end, { desc = "今のファイルを UTF-8（BOM なし）で保存し直す" })

-- :EncToSjis … 今のファイルを CP932（Shift_JIS）にして保存する
-- CP932 で揃っている社内プロジェクトで、新しく作ったファイル（既定は UTF-8）を
-- 周りに合わせる時に使う。混在を増やさないための出口。
vim.api.nvim_create_user_command("EncToSjis", function()
  vim.bo.fileencoding = "cp932"
  vim.bo.bomb = false
  vim.cmd.write()
end, { desc = "今のファイルを CP932（Shift_JIS）で保存し直す" })

-- 外部コマンドの出力（:make・:cfile・quickfix）が CP932 で化ける時は、その場で
--   :set makeencoding=char
-- を打つ（char＝OS のロケール＝このPCでは CP932）。常時入れていないのは、LazyVim が
-- grepprg を rg にしているので :grep の出力（UTF-8）まで変換されて、逆に化けるため。
