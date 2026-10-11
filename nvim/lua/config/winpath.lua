-- パスを Windows 側（エクスプローラ・クリップボード）に出すための小さな口。
--
-- なぜ別モジュールか: 同じ 2 つをバッファ側（config/keymaps.lua）と snacks explorer 側
-- （plugins/snacks.lua）の両方から呼ぶ。片方だけ直して食い違うのを防ぐ。
--
-- 肝は Windows が受け取れる形に直してから渡すこと。Neovim も snacks
-- （Snacks.picker.util.path）もパスを / に正規化して返すが、Windows 側はそれを
-- 受け取れない場面がある:
--   explorer.exe /select, … / のままだと黙って無視され「ドキュメント」が開く
--   貼り付け先（アドレスバー・pwsh・Excel のリンク） … \ が期待される形
-- WSL で動かしている nvim では、そもそも Linux のパス（/home/... ・/mnt/c/...）を
-- 持っているので \ に替えるだけでは足りない＝wslpath -w で変換する。
local M = {}

--- Windows が解釈できる形にする。
---@param path string
---@return string|nil win_path, string|nil err
function M.to_win(path)
  -- 既に Windows 形式（C:/... ・C:\...）なら区切りを寄せるだけ
  if path:match("^%a:[/\\]") then
    return (path:gsub("/", "\\"))
  end
  -- Windows の nvim なら UNC（//wsl.localhost/...）もこの形で通る
  if vim.fn.has("win32") == 1 then
    return (path:gsub("/", "\\"))
  end
  -- WSL: Linux のパスを Windows から見た形に変換する。
  -- /mnt/c/x → C:\x ・/home/me/x → \\wsl.localhost\<distro>\home\me\x
  if vim.fn.executable("wslpath") == 0 then
    return nil, "Windows のパスに変換できません（wslpath が無い＝WSL ではない）:\n" .. path
  end
  local r = vim.system({ "wslpath", "-w", path }):wait()
  if r.code ~= 0 then
    return nil, "wslpath が失敗しました:\n" .. (r.stderr or "")
  end
  return (vim.trim(r.stdout))
end

--- エクスプローラを開いて、そのファイル（フォルダ）を選択状態にする。
--- 親フォルダを開くだけなら vim.ui.open(dirname) でも足りるが、/select で当たりが付く。
---@param path string
function M.reveal(path)
  -- 実体を先に見る: /select は存在しないパスを渡されると黙って「ドキュメント」を
  -- 開くので、ここで止めないと「何か開いたが目的の場所ではない」になる
  if not vim.uv.fs_stat(path) then
    return vim.notify("そのパスがありません:\n" .. path, vim.log.levels.ERROR)
  end
  local win, err = M.to_win(path)
  if not win then
    return vim.notify(err, vim.log.levels.ERROR)
  end
  -- explorer.exe は成功しても終了コード 1 を返す＝コードでは成否を判定できない。
  -- 判定できるのは「起動できたか」だけ（exe が無ければ spawn が nil, err を返す）。
  --
  -- Windows では vim.system を使わない: 空白を含む引数は libuv が丸ごと " で囲むので
  -- "/select,C:\a b\f.txt" になり、explorer はこれを読めずに「ドキュメント」を開く
  -- （, を含むパスも同じく化ける）。explorer が読めるのは /select,"C:\a b\f.txt" の形
  -- だけ＝パスだけを自分で囲み、verbatim で libuv の引用を止めてそのまま渡す。
  local is_win = vim.fn.has("win32") == 1
  local handle, e
  handle, e = vim.uv.spawn("explorer.exe", {
    args = { is_win and ('/select,"' .. win .. '"') or ("/select," .. win) },
    verbatim = is_win,
    detached = true,
  }, function()
    handle:close()
  end)
  if not handle then
    vim.notify(
      "explorer.exe を起動できません（Windows 以外・WSL interop が無効・PATH に無い）:\n" .. tostring(e),
      vim.log.levels.ERROR
    )
  end
end

--- 絶対パスを Windows 形式でクリップボードへ。
--- + と " の両方に入れる: clipboard=unnamedplus でも setreg は指定したレジスタにしか
--- 書かないので、p で貼れるようにするには " も要る。
---@param path string
function M.copy(path)
  local p, err = M.to_win(path)
  if not p then
    -- 変換できなくても手ぶらで返さない（Linux のパスのまま渡して、その旨を言う）
    p = path
    vim.notify(err .. "\nLinux のパスのままコピーしました", vim.log.levels.WARN)
  end
  vim.fn.setreg("+", p)
  vim.fn.setreg('"', p)
  vim.notify(p, vim.log.levels.INFO, { title = "Copied path" })
end

return M
