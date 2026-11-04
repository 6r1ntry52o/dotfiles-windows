-- CP932（Shift_JIS）の C/C++ を、clangd に UTF-8 で見せる（tools/bin/utf8-mirror.exe を呼ぶ）。
-- 有効にするのは plugins/clangd.lua。
--
-- なぜ要るか: clangd はソースを UTF-8 として読む。CP932 のヘッダでは、行末が「表」「能」など
-- 2 バイト目が \ の文字のコメントが行継続になり、次の行（宣言・メンバ・#endif）が clangd から消える
-- （無いはずのエラーが出る・定義に飛べない）。日本語より後ろの列もずれる。UTF-16 のヘッダは読めない。
-- ソースは MSVC のために今の文字コードのまま置きたいので、UTF-8 に直した写しを、元のパスのまま
-- clangd に見せる（clang の VFS overlay）。写しは %LOCALAPPDATA%\utf8-mirror、clangd への指定は
-- %LOCALAPPDATA%\clangd\config.yaml のリポごとの節（リポには何も書かない。仕組み＝
-- tools/cp932/Utf8Mirror.cs の冒頭）。
--
-- いつ動くか:
--   CP932 の C/C++ を開いた・保存した時 … そのリポ（.git か .svn のある所、無ければ
--     compile_commands.json のある所）で有効にして、clangd を再起動する
--   有効なリポで C/C++ を開いた時・フォーカスが戻った時・ターミナル（lazygit など）を閉じた時
--     … 写しを今のソースに合わせる（裏で。更新日時と大きさが変わったファイルだけ読む）
--   有効なリポで C/C++ を保存した時 … そのファイルの写しを替えてから、clangd に保存を知らせる
--     （clangd は保存の知らせで開いているファイルを読み直す。この autocmd は LSP より先に作るので先に走る）
--   :Utf8Mirror [status|on|off|sync]
--
-- 限界: clangd の裏のインデックスは .cpp 本体を写しでなくディスクから読む（写しが効くのは
-- #include されるファイルだけ）。開いているファイルはエディタが UTF-8 で渡すので問題ない。
local M = {}

local PATTERNS = { "*.c", "*.cc", "*.cpp", "*.cxx", "*.h", "*.hh", "*.hpp", "*.hxx", "*.inl", "*.ipp", "*.tcc", "*.tlh", "*.tli" }
local TITLE = "UTF-8 の写し（clangd）"

---utf8-mirror.exe（install.ps1 が <dotfiles>\tools\bin にビルドする）。nvim の設定は junction なので実体から辿る
---@return string|nil
local function exe()
  local here = vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2))
  if not here then
    return nil
  end
  local repo = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(here))))
  local path = vim.fs.joinpath(repo, "tools", "bin", "utf8-mirror.exe")
  return vim.uv.fs_stat(path) and path or nil
end

local function key(path)
  return vim.fs.normalize(path):lower()
end

---file のリポ。リポ全体を写す（compile_commands.json がサブフォルダにあっても、ヘッダはリポ中にある）
---@return string|nil
local function root_of(file)
  return vim.fs.root(file, { ".git", ".svn" }) or vim.fs.root(file, "compile_commands.json")
end

---@type table<string, string>|nil key(root) → root。clangd の設定に節があるリポ（最初に要った時に読む）
local enabled
local pending = {} -- key(root) → true（enable の途中）
local last_sync = {} -- key(root) → vim.uv.now()
local warned = false

---@return table<string, string>
local function load_enabled()
  if enabled then
    return enabled
  end
  enabled = {}
  local bin = exe()
  if not bin then
    return enabled
  end
  local res = vim.system({ bin, "status", "--json" }, { text = true }):wait(5000)
  local ok, list = pcall(vim.json.decode, res.stdout or "")
  if res.code == 0 and ok and type(list) == "table" then
    for _, item in ipairs(list) do
      enabled[key(item.root)] = item.root
    end
  end
  return enabled
end

---utf8-mirror を裏で呼ぶ。on_done(結果の JSON か nil, 出力)
local function run(args, on_done)
  local bin = exe()
  if not bin then
    if not warned then
      warned = true
      vim.notify("tools/bin/utf8-mirror.exe が無い（dotfiles で install.ps1 を流す）", vim.log.levels.WARN, { title = TITLE })
    end
    return
  end
  vim.system(vim.list_extend({ bin }, args), { text = true }, function(res)
    vim.schedule(function()
      local ok, info = pcall(vim.json.decode, res.stdout or "")
      on_done(ok and type(info) == "table" and info or nil, vim.trim((res.stderr or "") .. (res.stdout or "")))
    end)
  end)
end

---動いている clangd を再起動する（設定の節を読ませ、インデックスを作り直させる）。再起動したら true
local function restart_clangd()
  if #vim.lsp.get_clients({ name = "clangd" }) == 0 then
    return false
  end
  return pcall(vim.cmd, "LspRestart clangd")
end

---写しを今のソースに合わせる（裏で）。force でなければ 10 秒に 1 回まで
local function sync(root, force)
  local k = key(root)
  local now = vim.uv.now()
  if not force and last_sync[k] and now - last_sync[k] < 10000 then
    return
  end
  last_sync[k] = now
  run({ "sync", root, "--json" }, function(info, out)
    if not info or #info.errors > 0 then
      vim.notify("写しの更新に失敗: " .. root .. "\n" .. out:sub(-600), vim.log.levels.WARN, { title = TITLE })
    elseif force then
      vim.notify(("%d 件（+%d ~%d -%d）: %s"):format(info.mirrored, info.added, info.updated, info.removed, root), vim.log.levels.INFO, { title = TITLE })
    end
  end)
end

local function enable(root)
  local k = key(root)
  if pending[k] then
    return
  end
  pending[k] = true
  run({ "enable", root, "--json" }, function(info, out)
    pending[k] = nil
    if not info then
      return vim.notify("有効にできなかった: " .. root .. "\n" .. out:sub(-600), vim.log.levels.ERROR, { title = TITLE })
    end
    load_enabled()[k] = root
    last_sync[k] = vim.uv.now()
    local restarted = restart_clangd()
    vim.notify(
      ("CP932 のソースを UTF-8 に直した写しで clangd に読ませる（%d 件・%s）。%s止める＝:Utf8Mirror off"):format(
        info.mirrored,
        root,
        restarted and "clangd は再起動した。" or ""
      ),
      vim.log.levels.INFO,
      { title = TITLE }
    )
  end)
end

---C/C++ のバッファを開いた・保存した時。有効なリポなら写しを合わせ、CP932 なら有効にする
local function on_buffer(buf, saved)
  if vim.bo[buf].buftype ~= "" then
    return
  end
  local file = vim.api.nvim_buf_get_name(buf)
  local root = file ~= "" and root_of(file)
  if not root then
    return
  end
  if load_enabled()[key(root)] then
    if saved then
      -- 待つ（37 ms ほど）: この後 LSP が clangd に保存を知らせ、clangd が開いているファイルを読み直す
      local bin = exe()
      if bin then
        vim.system({ bin, "sync", root, "--file", file, "--json" }, { text = true }):wait(5000)
      end
    else
      sync(root)
    end
  elseif vim.bo[buf].fileencoding == "cp932" then
    enable(root)
  end
end

---開いている C/C++ のバッファがある、有効なリポの写しを合わせる（外で git checkout などをした後）
local function sync_open_roots()
  if not enabled or vim.tbl_isempty(enabled) then
    return
  end
  local roots = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.bo[buf].filetype
    if vim.api.nvim_buf_is_loaded(buf) and (ft == "c" or ft == "cpp") then
      local root = root_of(vim.api.nvim_buf_get_name(buf))
      if root and enabled[key(root)] then
        roots[key(root)] = root
      end
    end
  end
  for _, root in pairs(roots) do
    sync(root)
  end
end

local function command(a)
  local sub = a.args ~= "" and a.args or "status"
  local file = vim.api.nvim_buf_get_name(0)
  local root = root_of(file ~= "" and file or assert(vim.uv.cwd()))
  if not root then
    return vim.notify("リポ（.git・.svn・compile_commands.json）の中で使う", vim.log.levels.WARN, { title = TITLE })
  end
  local k = key(root)
  if sub == "on" then
    enable(root)
  elseif sub == "off" then
    run({ "disable", root, "--json" }, function(info, out)
      if not info then
        return vim.notify("外せなかった: " .. out:sub(-600), vim.log.levels.ERROR, { title = TITLE })
      end
      load_enabled()[k] = nil
      local restarted = restart_clangd()
      vim.notify(
        ("外した（clangd の設定の節と写しを消した%s）: %s"):format(restarted and "・clangd を再起動した" or "", root),
        vim.log.levels.INFO,
        { title = TITLE }
      )
    end)
  elseif sub == "sync" then
    if not load_enabled()[k] then
      return vim.notify("このリポでは使っていない（:Utf8Mirror on で有効にする）: " .. root, vim.log.levels.WARN, { title = TITLE })
    end
    sync(root, true)
  else
    run({ "status", root, "--json" }, function(info)
      local item = info and info[1]
      vim.notify(
        item and ("使っている: %s\n写し %d 件（%s）"):format(root, item.mirrored, item.state)
          or ("使っていない: %s\nCP932 の C/C++ を開くと有効になる（手で＝:Utf8Mirror on）"):format(root),
        vim.log.levels.INFO,
        { title = TITLE }
      )
    end)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("dotfiles_utf8_mirror", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "c", "cpp" },
    callback = function(ev)
      on_buffer(ev.buf, false)
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = PATTERNS,
    callback = function(ev)
      on_buffer(ev.buf, true)
    end,
  })
  vim.api.nvim_create_autocmd({ "FocusGained", "TermClose" }, {
    group = group,
    callback = sync_open_roots,
  })
  vim.api.nvim_create_user_command("Utf8Mirror", command, {
    nargs = "?",
    complete = function()
      return { "status", "on", "off", "sync" }
    end,
    desc = "CP932 の C/C++ を clangd に UTF-8 で見せる（status・on・off・sync）",
  })
end

return M
