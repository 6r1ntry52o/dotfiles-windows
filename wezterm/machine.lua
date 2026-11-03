-- この PC だけの値を 1 か所から読む（nvim 側の lua/config/machine.lua と同じファイルを見る）。
-- 正本＝ホームの `~/.dotfiles.json`。雛形＝リポ直下の dotfiles.example.json。
-- リポに PC 固有の値を書かない＝どの PC のどこに clone しても同じ設定が動く。
local wezterm = require("wezterm")

local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
local path = home:gsub("\\", "/") .. "/.dotfiles.json"

local M = { path = path, config = {} }

local f = io.open(path, "r")
if f then
  local body = f:read("*a")
  f:close()
  local ok, decoded = pcall(wezterm.json_parse, body)
  if ok and type(decoded) == "table" then
    M.config = decoded
  else
    -- 設定を壊さない（既定値で続ける）。ログは `wezterm cli` のデバッグ出力に出る
    wezterm.log_error(path .. " を JSON として読めません")
  end
end

-- wezterm セクション（font_size）
M.wezterm = type(M.config.wezterm) == "table" and M.config.wezterm or {}

-- Obsidian vault の場所（"vault"・~ は展開する）。未設定なら nil
if type(M.config.vault) == "string" and M.config.vault ~= "" then
  M.vault = (M.config.vault:gsub("^~", home))
end

return M
