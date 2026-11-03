-- まだ無いノートへのリンクを踏んだ時に、Obsidian ならどこに作るか（lua/config/jump.lua の Ctrl+Enter）。
-- 設定はリポに書かず、その PC の vault の .obsidian から読む（PC ごとに違ってよい）。
--   * .obsidian/app.json の newFileLocation（新規ノートの既定の場所）:
--     root＝vault 直下（Obsidian の既定）・current＝今のノートと同じフォルダ・folder＝newFileFolderPath
--   * dated-folders プラグイン（有効な時だけ）: <baseFolder>/YYYY/… の日付のフォルダへ回す。
--     計算はプラグイン（https://github.com/6r1ntry52o/dated-folders 0.3.0）の main.js と同じ。
--     日付のフォルダが無ければ作る（プラグインの ensure と同じ）
-- フォルダを書いたリンク（[[a/b]]）は、どちらの設定にも依らず書いたとおりの場所（vault から。
-- ./ ../ で始まれば今のノートから）。vault の外では今のファイルのフォルダから。
local M = {}

local DAY = 24 * 60 * 60

-- dated-folders の既定値（main.js の D）
local DATED_DEFAULTS =
  { baseFolder = "", grain = "day", weekStart = 1, weekNumber = true, linkScope = "all", extensions = { "md" } }

local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local body = f:read("*a")
  f:close()
  local ok, value = pcall(vim.json.decode, body)
  return ok and type(value) == "table" and value or nil
end

---有効な dated-folders の設定（入っていない・無効なら nil）
local function dated_settings(root)
  local enabled = read_json(vim.fs.joinpath(root, ".obsidian", "community-plugins.json")) or {}
  if not vim.tbl_contains(enabled, "dated-folders") then
    return nil
  end
  local data = read_json(vim.fs.joinpath(root, ".obsidian", "plugins", "dated-folders", "data.json")) or {}
  local s = vim.tbl_extend("force", DATED_DEFAULTS, data)
  if type(s.extensions) ~= "table" or #s.extensions == 0 then
    s.extensions = { "md" }
  end
  return s
end

---その日の正午（日をまたぐ足し引きで時刻のずれが日付に響かないように）
local function noon(d)
  return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

---ISO 8601 の週番号（月曜始まり・その週の木曜がある年の何週目か）
local function iso_week(time)
  local function thursday(t)
    local d = os.date("*t", t)
    return noon(d) + (3 - (d.wday + 5) % 7) * DAY -- wday は日曜＝1
  end
  local th = thursday(time)
  local first = thursday(os.time({ year = os.date("*t", th).year, month = 1, day = 4, hour = 12 }))
  return 1 + math.floor((th - first) / (7 * DAY) + 0.5)
end

---dated-folders が time に新しいノートを入れるフォルダ（vault からの相対・/ 区切り）。
---year＝YYYY・month＝YYYY/MM・week＝YYYY/MM-DD(Wnn)（週の初日）・day＝YYYY/MM/DD
---@param s table dated-folders の設定
---@param time integer
---@return string
function M.dated_folder(s, time)
  local d = os.date("*t", time)
  if s.grain == "week" then
    -- 週番号を付ける時は月曜始まりに固定（ISO の週）
    local start = s.weekNumber and 1 or (tonumber(s.weekStart) or 1)
    d = os.date("*t", noon(d) - ((d.wday - 1 - start + 7) % 7) * DAY)
  end
  local y, m, dd = tostring(d.year), ("%02d"):format(d.month), ("%02d"):format(d.day)
  local parts
  if s.grain == "year" then
    parts = { y }
  elseif s.grain == "month" then
    parts = { y, m }
  elseif s.grain == "week" then
    parts = { y, s.weekNumber and ("%s-%s(W%02d)"):format(m, dd, iso_week(noon(d))) or (m .. "-" .. dd) }
  else
    parts = { y, m, dd }
  end
  local base = (s.baseFolder or ""):gsub("^/+", ""):gsub("/+$", "")
  if base ~= "" then
    table.insert(parts, 1, base)
  end
  return table.concat(parts, "/")
end

---リンクから作るノートを dated-folders が日付のフォルダへ回すか（main.js の P）
local function routed(s, source_rel)
  if s.linkScope == "none" then
    return false
  end
  local base = (s.baseFolder or ""):gsub("^/+", ""):gsub("/+$", "")
  if s.linkScope == "inside" and base ~= "" and source_rel ~= base and not vim.startswith(source_rel, base .. "/") then
    return false
  end
  return vim.tbl_contains(s.extensions, "md")
end

local function full(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

---先の無いリンクから作るノートのフルパス。
---@param link string リンクに書かれたパス（#見出しは除く・拡張子は無くてよい）
---@param source string リンクのあるファイルのフルパス
---@param time? integer 今（テスト用）
---@return string
function M.path(link, source, time)
  link = link:gsub("\\", "/")
  if vim.fn.fnamemodify(link, ":e"):lower() ~= "md" then
    link = link .. ".md"
  end
  source = vim.fs.normalize(source)
  local here = vim.fs.dirname(source)
  local vault = require("config.vault")
  local root = vault.root()
  if not vault.contains(source) or link:match("^%.%.?/") then
    return full(vim.fs.joinpath(here, link))
  end
  if link:find("/", 1, true) then
    return full(vim.fs.joinpath(root, link))
  end
  local folder
  local s = dated_settings(root)
  if s and routed(s, source:sub(#root + 2)) then
    folder = vim.fs.joinpath(root, M.dated_folder(s, time or os.time()))
  else
    local app = read_json(vim.fs.joinpath(root, ".obsidian", "app.json")) or {}
    if app.newFileLocation == "current" then
      folder = here
    elseif app.newFileLocation == "folder" and type(app.newFileFolderPath) == "string" then
      folder = vim.fs.joinpath(root, app.newFileFolderPath)
    else
      folder = root
    end
  end
  return full(vim.fs.joinpath(folder, link))
end

return M
