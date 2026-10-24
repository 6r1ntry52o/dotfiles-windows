-- clangd がどの構成（Debug|x64 など）で解析しているかを確かめる（<leader>mi とステータスライン）。
-- 有効にするのは plugins/clangd.lua（lazymsbuild が PATH にある時だけ）。
--
-- 2 つの層の答えを並べる。
--   公開中の DB   … lazymsbuild に聞く（`lazymsbuild --json check` の profile と sync）。
--                   compile_commands.json を書くのは lazymsbuild なので、これが正本。
--   clangd の解析 … 動いている clangd 自身のログ。clangd はファイルを解析するたびに
--                   「ASTWorker building file <ファイル> version N with command <由来>」と
--                   実際の引数を stderr に出す（Neovim はそれを vim.lsp.log.error に渡す）。
--                   その引数を、lazymsbuild が構成ごとに持つ DB（状態ディレクトリの
--                   profiles\<ソリューション>-<hash>\<構成>_<プラットフォーム>.json）の
--                   同じファイルの項目と突き合わせ、構成ごとに違う引数（/MDd と /MD、
--                   _DEBUG と NDEBUG、/Fox64\Debug\ など）がどれだけ入っているかで決める。
--
-- なぜ要るか: clangd は compile_commands.json が変わっても、開いているファイルを自分からは
-- 解析し直さない。次の編集か保存（:w）で DB を読み直す（DB の更新から 5 秒ほど後。clangd 23 で
-- 2026-10-25 に実測）。構成を切り替えた直後は「DB は Release、clangd は Debug のまま」がありうる。
-- 目で確かめる時は、#ifdef _DEBUG の中が Release ではコメントの色になる（clangd は無効な区間を
-- comment のトークンで送る）。

local M = {}

local uv = vim.uv

---パスの比較用のキー（Windows は大文字小文字と / \ を区別しない）
---@param path string
local function key(path)
  return (path:gsub("/", "\\")):lower()
end

---@param path string
---@param size? integer 先頭だけ読む時のバイト数
local function read(path, size)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local text = f:read(size or "*a")
  f:close()
  return text
end

---------------------------------------------------------------------------
-- clangd のログ
---------------------------------------------------------------------------

---@class clangd_profile.Record
---@field file string clangd が解析したファイル
---@field heuristic string コマンドの由来。"" = DB の項目・"inferred from X" = X の項目を借りた・"clangd fallback" = DB 外
---@field argv string 実際の引数（clangd の書式のまま）
---@field clock string 解析した時刻
---@field seq integer

---@type table<string, clangd_profile.Record> key(ファイル) → 最後の解析
local records = {}
local seq = 0
---clangd の stderr の、行や記録の途中で切れた残り（コマンド名ごと）
local partial = {}
---記録が増えた時に呼ぶ（setup が入れる）
local on_record

---clangd の stderr の 1 チャンク。vim.lsp.log.error の中（fast event）から呼ばれるので、
---ここでは文字列を読むだけにして、残りは vim.schedule に回す。
local function feed(name, chunk)
  local text = ((partial[name] or "") .. chunk):gsub("\r\n", "\n")
  local rest, found = 1, false
  for file, heuristic, argv, finish in
    text:gmatch("ASTWorker building file ([^\n]-) version %d+ with command ([^\n]*)\n%[[^\n]*%]\n([^\n]*)\n()")
  do
    seq = seq + 1
    records[key(file)] =
      { file = file, heuristic = vim.trim(heuristic), argv = argv, clock = os.date("%H:%M:%S"), seq = seq }
    rest, found = finish, true
  end
  local tail = text:sub(rest)
  local open = tail:find("ASTWorker building file", 1, true)
  -- 記録の途中で切れていれば記録の頭から、そうでなければ最後の行の途中だけを残す
  partial[name] = (open and #tail - open < 65536) and tail:sub(open) or tail:match("[^\n]*$")
  if found and on_record then
    vim.schedule(on_record)
  end
end

local hooked = false

---clangd の stderr を横から読む。Neovim は LSP サーバの stderr を vim.lsp.log.error('rpc',
---<コマンド>, 'stderr', <チャンク>) に渡す（0.10 は rpc.lua、0.11 は _transport.lua）。
---ログのファイル（lsp.log）は他の Neovim と共有なので読まない。
local function hook()
  local ok, log = pcall(require, "vim.lsp.log")
  if hooked or not ok or type(log.error) ~= "function" then
    return
  end
  hooked = true
  local original = log.error
  log.error = function(...)
    local tag, cmd, kind, chunk = ...
    if tag == "rpc" and kind == "stderr" and type(chunk) == "string" then
      local name = type(cmd) == "table" and cmd[1] or cmd -- 0.10 はコマンド全体、0.11 は cmd[1]
      if type(name) == "string" and (name:match("[^/\\]+$") or ""):lower():find("^clangd") then
        pcall(feed, name, chunk)
      end
    end
    return original(...)
  end
end

---clangd の引数の書式（空白区切り・空白や \ や " を含むものは "…" で C の escape）を分ける。
---@param s string
---@return string[]
local function split_argv(s)
  local args, i, n = {}, 1, #s
  local escapes = { n = "\n", t = "\t", r = "\r" }
  while i <= n do
    local c = s:sub(i, i)
    if c == " " then
      i = i + 1
    elseif c == '"' then
      local buf = {}
      i = i + 1
      while i <= n do
        local ch = s:sub(i, i)
        if ch == "\\" then
          local nx = s:sub(i + 1, i + 1)
          if nx == "x" then
            table.insert(buf, string.char(tonumber(s:sub(i + 2, i + 3), 16) or 63))
            i = i + 4
          else
            table.insert(buf, escapes[nx] or nx)
            i = i + 2
          end
        elseif ch == '"' then
          i = i + 1
          break
        else
          table.insert(buf, ch)
          i = i + 1
        end
      end
      table.insert(args, table.concat(buf))
    else
      local j = s:find(" ", i, true) or n + 1
      table.insert(args, s:sub(i, j - 1))
      i = j
    end
  end
  return args
end

---------------------------------------------------------------------------
-- lazymsbuild（公開中の DB と、構成ごとの DB）
---------------------------------------------------------------------------

---@class clangd_profile.Project
---@field path table `lazymsbuild --json path`（solution・state・db_file・root）
---@field check? table `lazymsbuild --json check`（profile・sync）
---@field dir string lazymsbuild に -C で渡すディレクトリ
---@field version integer 聞き直すたびに増える（判定のキャッシュを捨てる目印）
---@field busy? boolean
---@field again? boolean

---@type table<string, clangd_profile.Project> key(ソリューション) → プロジェクト
local projects = {}
---key(ディレクトリ) → key(ソリューション) | false（lazymsbuild のソリューションの外）| true（問い合わせ中）
local dirs = {}

local function redraw()
  if not pcall(function()
    require("lualine").refresh()
  end) then
    vim.cmd.redrawstatus()
  end
end

---`lazymsbuild -C <dir> --json <args>`。check は問題があると終了コード 1 でも JSON を出す。
---@param wait? boolean 終わるまで待つ（<leader>mi）
local function lazymsbuild(args, dir, callback, wait)
  local cmd = vim.list_extend({ "lazymsbuild", "-C", dir, "--json" }, args)
  local function done(res)
    local ok, value = pcall(vim.json.decode, res.stdout or "")
    callback(ok and type(value) == "table" and value or nil)
  end
  if wait then
    done(vim.system(cmd, { text = true }):wait(30000))
  else
    vim.system(cmd, { text = true }, function(res)
      vim.schedule(function()
        done(res)
      end)
    end)
  end
end

---公開中の DB を lazymsbuild に聞き直す。
local function refresh(project, wait)
  if project.busy and not wait then
    project.again = true
    return
  end
  project.busy = true
  lazymsbuild({ "check" }, project.dir, function(check)
    project.busy = false
    project.check = check
    project.version = project.version + 1
    if project.again then
      project.again = false
      return refresh(project)
    end
    redraw()
  end, wait)
end

local timers = {}

---状態ディレクトリを見張る。ビルドと sync は status.json、TUI で構成を選び直すと state.json が変わる。
local function watch(project)
  local state = project.path.state
  vim.fn.mkdir(state, "p")
  local handle = uv.new_fs_event()
  if not handle then
    return
  end
  handle:start(state, {}, function(err, name)
    if err or (name ~= "status.json" and name ~= "state.json") then
      return
    end
    local timer = timers[state] or uv.new_timer()
    timers[state] = timer
    timer:stop()
    timer:start(
      300,
      0,
      vim.schedule_wrap(function()
        -- ビルド中は status.json が毎秒書き換わる。聞き直すのは終わってから
        local ok, status = pcall(vim.json.decode, read(vim.fs.joinpath(state, "status.json")) or "")
        if ok and type(status) == "table" and (status.state == "building" or status.state == "syncing") then
          return
        end
        refresh(project)
      end)
    )
  end)
end

---file が入る lazymsbuild のプロジェクト。知らなければ問い合わせを始めて nil を返す。
---@param file string
---@param wait? boolean 問い合わせが終わるまで待つ
---@return clangd_profile.Project|nil
local function project_for(file, wait)
  local dir = vim.fs.dirname(file)
  local dk = key(dir)
  if dirs[dk] == nil or (wait and dirs[dk] == true) then
    dirs[dk] = true
    lazymsbuild({ "path" }, dir, function(path)
      if not (path and type(path.solution) == "string" and type(path.state) == "string") then
        dirs[dk] = false
        return
      end
      local sk = key(path.solution)
      dirs[dk] = sk
      if not projects[sk] then
        projects[sk] = { path = path, dir = dir, version = 0 }
        watch(projects[sk])
        refresh(projects[sk], wait)
      end
    end, wait)
  end
  local sk = dirs[dk]
  return type(sk) == "string" and projects[sk] or nil
end

---このソリューションの、構成ごとの DB。meta は先頭だけ読む（後ろの entries は大きい）。
---@return { profile: string, file: string }[]
local function profile_dbs(project)
  local list = {}
  local base = vim.fs.joinpath(project.path.state, "profiles")
  local function field(head, name)
    local raw = head:match('"' .. name .. '":%s*"(.-)"%s*[,}\n]')
    return raw and (raw:gsub("\\(.)", { ["\\"] = "\\", ['"'] = '"', ["/"] = "/" }))
  end
  for dir, kind in vim.fs.dir(base) do
    if kind == "directory" then
      for name in vim.fs.dir(vim.fs.joinpath(base, dir)) do
        if name:match("%.meta%.json$") then
          local head = read(vim.fs.joinpath(base, dir, name), 8192) or ""
          local solution, profile = field(head, "solution"), field(head, "profile")
          if solution and profile and key(solution) == key(project.path.solution) then
            local db = vim.fs.joinpath(base, dir, (name:gsub("%.meta%.json$", ".json")))
            table.insert(list, { profile = profile, file = db })
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    return a.profile < b.profile
  end)
  return list
end

---DB の中の file の引数。lazymsbuild は 1 項目を「"file": …」の次の行に「"arguments": [ … ]」と
---1 行で書くので、その行だけ decode する（大きいソリューションでは DB 全体の decode が重い）。
---書き方が違えば全体を読む。
local function find_args(db, file)
  local text = read(db)
  if not text then
    return nil
  end
  local needle = ('"file": "%s"'):format((file:gsub("\\", "\\\\"))):lower()
  local at = text:lower():find(needle, 1, true)
  if at then
    local ok, args = pcall(vim.json.decode, text:match('^[^\n]*\n%s*"arguments": (%[[^\n]*%])', at) or "")
    if ok and type(args) == "table" then
      return args
    end
  end
  local ok, list = pcall(vim.json.decode, text)
  for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
    if type(entry) == "table" and type(entry.file) == "string" and key(entry.file) == key(file) then
      return entry.arguments
    end
  end
end

---DB ごとに、引いたファイルの引数を覚える（DB の大きさと更新時刻が変われば捨てる）
local args_cache = {}

local function entry_args(db, file)
  local stat = uv.fs_stat(db)
  if not stat then
    return nil
  end
  local stamp = ("%d:%d:%d"):format(stat.size, stat.mtime.sec, stat.mtime.nsec)
  local cache = args_cache[db]
  if not cache or cache.stamp ~= stamp then
    cache = { stamp = stamp, files = {} }
    args_cache[db] = cache
  end
  local fk = key(file)
  if cache.files[fk] == nil then
    cache.files[fk] = find_args(db, file) or false
  end
  return cache.files[fk] or nil
end

---------------------------------------------------------------------------
-- 判定
---------------------------------------------------------------------------

---@class clangd_profile.Verdict
---@field kind "match"|"ambiguous"|"unmatched"|"other-db"|"fallback"|"no-record"
---@field profiles? string[] match は 1 つ、ambiguous は引数で見分けられない複数
---@field evidence? string[] 決め手になった引数
---@field source? string inferred の時、コマンドを借りたファイル
---@field record? clangd_profile.Record

local known = {}
for _, t in ipairs({ "/mdd", "/md", "/mtd", "/mt", "/od", "/o1", "/o2", "/ox", "_debug", "ndebug" }) do
  known[t] = true
end

---clangd の実際の引数を、構成ごとの DB の同じファイルの項目と比べる。
---@param record clangd_profile.Record
---@return clangd_profile.Verdict
local function judge(record, project)
  if record.heuristic:find("fallback", 1, true) then
    return { kind = "fallback", record = record }
  end
  local source = record.heuristic:match("^inferred from (.+)$")
  local file = source or record.file
  local argv = split_argv(record.argv)
  local drop = { [key(record.file)] = true, [key(file)] = true, ["--"] = true, ["--driver-mode=cl"] = true }
  local function set_of(args)
    local set = {}
    for i = 2, #args do -- 1 つ目はコンパイラ（clangd はパスの大文字小文字を変える）
      local t = args[i]:lower()
      if not drop[t] and not t:find("^%-resource%-dir=") then
        set[t] = true
      end
    end
    return set
  end
  local seen = set_of(argv)
  local candidates = {}
  for _, db in ipairs(profile_dbs(project)) do
    local args = entry_args(db.file, file)
    if args then
      table.insert(candidates, { profile = db.profile, set = set_of(args) })
    end
  end
  if #candidates == 0 then
    -- DB の項目で解析しているのに、lazymsbuild のどの構成にも無い＝別の compile_commands.json
    return { kind = "other-db", source = source, record = record }
  end
  -- 全構成に共通の引数を除いた「その構成だけの引数」が、clangd の引数にどれだけあるか
  local common = {}
  for t in pairs(candidates[1].set) do
    common[t] = #candidates > 1 or nil
  end
  for i = 2, #candidates do
    for t in pairs(common) do
      if not candidates[i].set[t] then
        common[t] = nil
      end
    end
  end
  local best, best_score, ties = nil, -1, {}
  for _, c in ipairs(candidates) do
    local own, hit, all, overlap = 0, 0, 0, 0
    for t in pairs(c.set) do
      all = all + 1
      overlap = overlap + (seen[t] and 1 or 0)
      if not common[t] then
        own = own + 1
        hit = hit + (seen[t] and 1 or 0)
      end
    end
    c.overlap = all > 0 and overlap / all or 0
    -- その構成だけの引数が無い（引数が全く同じ構成がある）時は、重なりだけで比べる
    local score = own > 0 and hit / own or c.overlap
    if score > best_score + 1e-9 then
      best, best_score, ties = c, score, { c.profile }
    elseif math.abs(score - best_score) <= 1e-9 then
      table.insert(ties, c.profile)
    end
  end
  if not best or best_score <= 0 or best.overlap < 0.6 then
    return { kind = "unmatched", source = source, record = record }
  end
  -- 決め手: その構成だけの引数のうち clangd にあるもの。見て分かるもの（ランタイム・最適化・
  -- _DEBUG・ターゲット）を先に、パスは出さない
  local evidence, others = {}, {}
  for i = 2, #argv do
    local t = argv[i]:lower()
    if best.set[t] and not common[t] and seen[t] then
      if known[t] or t:find("^%-%-target=") then
        table.insert(evidence, argv[i])
      elseif #t <= 24 and not t:find("\\", 1, true) then
        table.insert(others, argv[i])
      end
    end
  end
  vim.list_extend(evidence, others)
  evidence = vim.list_slice(evidence, 1, 4)
  return {
    kind = #ties > 1 and "ambiguous" or "match",
    profiles = ties,
    evidence = evidence,
    source = source,
    record = record,
  }
end

local verdicts = {} -- key(ファイル) → { seq, version, value }

---@return clangd_profile.Verdict
local function verdict(file, project)
  local fk = key(file)
  local record = records[fk]
  if not record then
    return { kind = "no-record" }
  end
  local cached = verdicts[fk]
  if cached and cached.seq == record.seq and cached.version == project.version then
    return cached.value
  end
  local value = judge(record, project)
  verdicts[fk] = { seq = record.seq, version = project.version, value = value }
  return value
end

---公開中の DB の構成。lazymsbuild が「選んでいる構成の DB と同じ」と答えた時だけ。
local function published(project)
  local check = project.check
  return check and check.sync == "in-sync" and type(check.profile) == "string" and check.profile or nil
end

---clangd の構成と公開中の DB の構成が食い違っているか
local function differs(v, db)
  if not db then
    return false
  end
  if v.kind == "match" or v.kind == "ambiguous" then
    return not vim.tbl_contains(v.profiles, db)
  end
  return v.kind == "other-db" or v.kind == "unmatched" or v.kind == "fallback"
end

---------------------------------------------------------------------------
-- 表に出すもの
---------------------------------------------------------------------------

local function current()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local file = vim.api.nvim_buf_get_name(buf)
  if (ft ~= "c" and ft ~= "cpp") or file == "" then
    return nil
  end
  return file
end

local function line_of(file)
  local project = project_for(file)
  if not project then
    return "", false
  end
  local db = published(project)
  local v = verdict(file, project)
  local warn = differs(v, db)
  local text
  if v.kind == "match" then
    text = "clangd: " .. v.profiles[1]
  elseif v.kind == "ambiguous" then
    text = "clangd: " .. (vim.tbl_contains(v.profiles, db or "") and db or table.concat(v.profiles, " / "))
  elseif v.kind == "no-record" then
    return db and ("DB: " .. db) or "", false
  elseif v.kind == "fallback" then
    text = "clangd: DB の外"
  elseif v.kind == "other-db" then
    text = "clangd: 別の DB"
  else
    text = "clangd: ?"
  end
  if warn and db then
    text = text .. " (DB: " .. db .. ")"
  end
  return text, warn
end

---ステータスライン（lualine）。clangd が今のファイルを解析した構成。公開中の DB と違えば併記する。
function M.statusline()
  local file = current()
  if not file then
    return ""
  end
  local ok, text = pcall(line_of, file)
  return ok and text or ""
end

---lualine の色。食い違っている時だけ警告の色、ふだんは目立たない色。
function M.color()
  local file = current()
  local ok, _, warn = false, nil, false
  if file then
    ok, _, warn = pcall(line_of, file)
  end
  return { fg = Snacks.util.color(ok and warn and "DiagnosticWarn" or "Comment") }
end

---<leader>mi: 今のファイルについて、公開中の DB と clangd の解析を並べて出す。
function M.report()
  local file = current()
  if not file then
    return vim.notify("C/C++ のファイルで使う", vim.log.levels.WARN, { title = "clangd の構成" })
  end
  local project = project_for(file, true)
  if not project then
    return vim.notify(
      "lazymsbuild のソリューションの外: " .. file,
      vim.log.levels.WARN,
      { title = "clangd の構成" }
    )
  end
  refresh(project, true)
  local check = project.check or {}
  local db = published(project)
  local lines = { vim.fn.fnamemodify(file, ":~:.") }
  if db then
    table.insert(lines, ("DB（%s）: %s"):format(check.output or "compile_commands.json", db))
  elseif check.sync == "out-of-sync" then
    table.insert(
      lines,
      ("DB: 選んでいる %s の DB と中身が違う（lazymsbuild check で確かめる）"):format(
        check.profile or "?"
      )
    )
  elseif check.sync == "no-output" or check.sync == "no-database" then
    table.insert(lines, "DB: まだ無い（:CompileCommands かビルドで作る）")
  else
    table.insert(lines, "DB: lazymsbuild check の答えを読めない")
  end

  local v = verdict(file, project)
  local r = v.record
  local from = v.source and ("、%s のコマンドを借りている"):format(vim.fs.basename(v.source)) or ""
  local at = r and ("（%s%s）"):format(r.clock, from) or ""
  if v.kind == "match" or v.kind == "ambiguous" then
    table.insert(lines, ("clangd の解析: %s%s"):format(table.concat(v.profiles, " か "), at))
    if #v.evidence > 0 then
      table.insert(lines, "  決め手: " .. table.concat(v.evidence, " "))
    end
    if v.kind == "ambiguous" then
      table.insert(
        lines,
        "  （これらの構成は、このファイルの引数が同じで見分けられない）"
      )
    end
  elseif v.kind == "no-record" then
    table.insert(
      lines,
      "clangd の解析: まだ記録が無い（この Neovim の clangd が解析した後に分かる。編集か保存で解析が走る）"
    )
  elseif v.kind == "fallback" then
    table.insert(
      lines,
      "clangd の解析: DB にこのファイルが無く、clangd の既定のフラグで解析している" .. at
    )
  elseif v.kind == "other-db" then
    table.insert(
      lines,
      "clangd の解析: lazymsbuild のどの構成にも無いコマンド"
        .. at
        .. "。別の compile_commands.json（古い build\\ など）を読んでいる"
    )
  else
    table.insert(
      lines,
      "clangd の解析: どの構成の引数とも合わない"
        .. at
        .. "。.clangd の CompileFlags か、別の DB を読んでいる"
    )
  end

  local level = vim.log.levels.INFO
  if differs(v, db) then
    level = vim.log.levels.WARN
    table.insert(
      lines,
      "⚠ clangd は公開中の DB と違うコマンドで解析している。保存（:w）すると開いているファイルを読み直す（DB の更新から 5 秒ほど後）。直らなければ :LspRestart clangd"
    )
  elseif db and (v.kind == "match" or v.kind == "ambiguous") then
    table.insert(lines, "✔ 一致")
  end
  vim.notify(table.concat(lines, "\n"), level, { title = "clangd の構成" })
end

function M.setup()
  hook()
  on_record = redraw
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("dotfiles_clangd_profile", { clear = true }),
    pattern = { "c", "cpp" },
    callback = function(event)
      local name = vim.api.nvim_buf_get_name(event.buf)
      if name ~= "" then
        project_for(name) -- 先に lazymsbuild に聞いておく
      end
    end,
  })
  vim.keymap.set("n", "<leader>mi", M.report, { desc = "clangd がどの構成で解析しているか" })
end

-- テスト用
M._records = records
M._split_argv = split_argv
M._feed = feed

return M
