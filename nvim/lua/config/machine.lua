-- この PC だけの値を 1 か所から読む。
-- 正本＝ホームの `~/.dotfiles.json`（雛形＝リポ直下の dotfiles.example.json・
-- 無ければ install.ps1 が作る）。キーの説明は README の「PC ごとの設定」。
--
-- なぜリポに書かないか: vault の場所やフォルダ構成は PC ごとに違う。リポに絶対パスを
-- 書くと、別の PC・別の clone 先では黙って外れる。リポは「どこに置いても動く」ままにして、
-- PC 固有の値はこのファイル経由でホームの 1 枚から取る。
--
-- 無い / 壊れていても起動は止めない（その値が無いものとして扱う）。
local M = {}

local home = vim.uv.os_homedir() -- Windows は %USERPROFILE%
M.path = home and vim.fs.joinpath(home, ".dotfiles.json") or nil

local cache

---@return table
function M.get()
  if cache then
    return cache
  end
  cache = {}
  local f = M.path and io.open(M.path, "r")
  if f then
    local body = f:read("*a")
    f:close()
    local ok, decoded = pcall(vim.json.decode, body)
    if ok and type(decoded) == "table" then
      cache = decoded
    else
      vim.notify(M.path .. " を JSON として読めません", vim.log.levels.WARN)
    end
  end
  return cache
end

---文字列の値を取る。未設定（キーが無い・空文字）は nil。
---空文字を nil 扱いにするのは、install.ps1 が vault を自動で見つけられなかった時に
---`"vault": ""` のまま置かれるため。
---@param key string
---@return string|nil
function M.str(key)
  local v = M.get()[key]
  if type(v) == "string" and v ~= "" then
    return v
  end
end

return M
