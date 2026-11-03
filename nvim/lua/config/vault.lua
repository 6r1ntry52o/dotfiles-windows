-- Obsidian vault の中に居ることを色で分かるようにする（Obsidian の紫）。
-- vault の場所は `~/.dotfiles.json` の "vault"（lua/config/machine.lua）。未設定の PC では何もしない。
--
-- 色を変える場所は 2 つだけ:
--   * 各ペイン上端のファイル名（winbar）… lua/config/autocmds.lua が下の contains() で色を選ぶ。
--     分割して vault の中と外を並べても、どちらが vault かがペインごとに分かる。
--   * WezTerm のタブ … 今のバッファが vault の中かどうかを WezTerm へ通知する（下の notify）。
--     色を塗るのは wezterm/wezterm.lua。
-- モードの色・カーソル・背景は変えない（どれも別の意味を持っているため）。
--
-- obsidian.nvim の vim.b.obsidian_buffer を使わないのは、あれが md にしか立たないため
-- （vault の中の json や画像一覧でも「vault の中」と出したい）。
local M = {}

-- Obsidian のダークテーマの紫（--color-purple）。wezterm/wezterm.lua の TAB_VAULT_BG と同じ値
M.COLOR = "#a882ff"
local FG = "#1b1d2b" -- 明るい紫の上なので濃色（WezTerm のアクティブなタブと同じ組み合わせ）

-- 比べる形に揃える: / 区切り・~ を展開・末尾の / なし・小文字（Windows は大文字小文字を区別しない）
local function norm(path)
  return (vim.fs.normalize(path):gsub("/+$", ""):lower())
end

local vault = require("config.machine").str("vault")
local root = vault and norm(vault) or nil

---そのパスが vault の中か。
---@param path string
---@return boolean
function M.contains(path)
  if not root or path == "" then
    return false
  end
  local p = norm(path)
  return p == root or p:sub(1, #root + 1) == root .. "/"
end

---`~/.dotfiles.json` の vault の場所（未設定なら nil）。
---@return string|nil
function M.root()
  return vault and vim.fs.normalize(vault) or nil
end

---この PC の vault の一覧（起動画面に出す）。先頭が `~/.dotfiles.json` の vault、続けて Obsidian に
---登録されているもの（%APPDATA%\obsidian\obsidian.json・最近開いた順）。消えたフォルダは出さない。
---@return string[]
function M.registered()
  local paths = { vault }
  local appdata = vim.env.APPDATA
  local f = appdata and io.open(vim.fs.joinpath(appdata, "obsidian", "obsidian.json"), "r")
  if f then
    local body = f:read("*a")
    f:close()
    local ok, decoded = pcall(vim.json.decode, body)
    if ok and type(decoded) == "table" and type(decoded.vaults) == "table" then
      local known = vim.tbl_values(decoded.vaults)
      table.sort(known, function(a, b)
        return (a.ts or 0) > (b.ts or 0)
      end)
      for _, v in ipairs(known) do
        paths[#paths + 1] = v.path
      end
    end
  end
  local seen, list = {}, {}
  for i = 1, table.maxn(paths) do
    local path = paths[i]
    if path and not seen[norm(path)] and vim.uv.fs_stat(path) then
      seen[norm(path)] = true
      list[#list + 1] = vim.fs.normalize(path)
    end
  end
  return list
end

-- WezTerm のユーザー変数 in_vault を書く（OSC 1337 SetUserVar・値は base64）。
-- "1"＝vault の中・"0"＝外・""＝nvim は居ない（WezTerm はシェルの現在地で判定する）。
local sent
local function notify(value)
  if value == sent then
    return
  end
  sent = value
  require("config.wezterm").set_user_var("in_vault", value)
end

function M.setup()
  if not root then
    return
  end
  local group = vim.api.nvim_create_augroup("vault_color", { clear = true })

  -- ここで直に塗っても効かない。`nvim <file>` で起動すると LazyVim は config/autocmds.lua（ここを
  -- 呼んでいる）を colorscheme より先に読み込み（argc>0 の経路）、テーマが後から塗り潰す。
  -- その時の ColorScheme イベントも lazy.nvim が起動中に eventignore で潰すので拾えない
  -- （2026-10-05 に実測）。起動処理が終わってから＝vim.schedule で 1 回塗り、
  -- テーマを切り替えた時は ColorScheme で塗り直す。
  local function paint()
    vim.api.nvim_set_hl(0, "VaultWinbar", { fg = FG, bg = M.COLOR, bold = true })
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = paint })
  vim.schedule(paint)

  if vim.env.TERM_PROGRAM ~= "WezTerm" then
    return
  end
  -- 実ファイルのバッファに入った時だけ更新する。ファイルツリー・ターミナル・フロートでは
  -- 直前の状態を保つ（ツリーにカーソルを移すたびにタブの色が戻らないように）。
  local function update()
    local name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype == "" and name ~= "" then
      notify(M.contains(name) and "1" or "0")
    end
  end
  vim.api.nvim_create_autocmd("BufEnter", { group = group, callback = update })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      notify("")
    end,
  })
  update()
end

return M
