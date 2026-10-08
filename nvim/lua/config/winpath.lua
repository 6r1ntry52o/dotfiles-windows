-- パスを Windows 側（エクスプローラ・クリップボード）に出すための小さな口。
--
-- なぜ別モジュールか: 同じ 2 つをバッファ側（config/keymaps.lua）と snacks explorer 側
-- （plugins/snacks-explorer.lua）の両方から呼ぶ。片方だけ直して食い違うのを防ぐ。
--
-- 肝は区切りを \ に直してから渡すこと。Neovim も snacks（Snacks.picker.util.path）も
-- パスを / に正規化して返すが、Windows 側はそれを受け取れない場面がある:
--   explorer.exe /select, … / のままだと黙って無視され「ドキュメント」が開く
--   貼り付け先（アドレスバー・pwsh・Excel のリンク） … \ が期待される形
local M = {}

---@param path string
---@return string
function M.to_win(path)
  return (path:gsub("/", "\\"))
end

--- エクスプローラを開いて、そのファイル（フォルダ）を選択状態にする。
--- 親フォルダを開くだけなら vim.ui.open(dirname) でも足りるが、/select で当たりが付く。
---@param path string
function M.reveal(path)
  vim.system({ "explorer.exe", "/select," .. M.to_win(path) }, { detach = true })
end

--- 絶対パスを \ 区切りでクリップボードへ。
--- + と " の両方に入れる: clipboard=unnamedplus でも setreg は指定したレジスタにしか
--- 書かないので、p で貼れるようにするには " も要る。
---@param path string
function M.copy(path)
  local p = M.to_win(path)
  vim.fn.setreg("+", p)
  vim.fn.setreg('"', p)
  vim.notify(p, vim.log.levels.INFO, { title = "Copied path" })
end

return M
