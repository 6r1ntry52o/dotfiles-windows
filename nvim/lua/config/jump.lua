-- Ctrl+Enter … カーソルの下にあるものの行き先へ飛ぶ。C/C++ は実装へ、md はリンク先へ。
-- キーを張るのは c / cpp / markdown のバッファだけ（他のファイルタイプは今までどおり）。
--
-- <C-CR> は素の WezTerm + ConPTY では nvim に届かない（<CR> か <NL> に潰れる）。
-- nvim が動いているペインにだけ、wezterm/keybinds.lua が CSI 13;5u を送って区別させる。
-- そのために、nvim が居ることをユーザー変数 nvim で WezTerm へ知らせる（下の setup）。
local M = {}

----------------------------------------------------
-- C/C++
----------------------------------------------------
-- clangd の textDocument/implementation が返すのは「仮想関数の override」と「派生クラス」だけで、
-- ふつうの関数では空になる（LazyVim の gI が効かない時があるのはこのため）。
-- そこで implementation を先に聞き、空なら definition に落とす（2026-11-03 clangd 23.1 で実測）。
-- 型名の上では聞かない: implementation が派生クラスを返し、型そのものの定義へ行けなくなる。
local function on_type_name()
  local ok, node = pcall(vim.treesitter.get_node)
  return ok and node ~= nil and node:type() == "type_identifier"
end

function M.cpp()
  if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" }) == 0 then
    vim.notify("LSP が付いていません（:LspInfo で確認）", vim.log.levels.WARN)
    return
  end
  if on_type_name() then
    Snacks.picker.lsp_definitions()
    return
  end
  local buf, cursor = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
  vim.lsp.buf_request_all(buf, "textDocument/implementation", function(client)
    return vim.lsp.util.make_position_params(0, client.offset_encoding)
  end, function(results)
    -- 返事を待つ間に動いていたら、もう聞かれていない
    if vim.api.nvim_get_current_buf() ~= buf or not vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor) then
      return
    end
    for _, res in pairs(results) do
      if res.result and not vim.tbl_isempty(res.result) then
        Snacks.picker.lsp_implementations() -- 1 件なら飛ぶ・複数なら選ぶ
        return
      end
    end
    Snacks.picker.lsp_definitions()
  end)
end

----------------------------------------------------
-- Markdown
----------------------------------------------------
-- vault の中でも外でも同じ動きにするため、obsidian.nvim には頼らない（あちらは vault 内だけ。
-- <CR> で先の無いリンクを踏むと新規作成に進む）。ここは開くだけで、ファイルは作らない。

-- エディタで開かず、既定アプリに渡す拡張子
local EXTERNAL = {}
for ext in ("png jpg jpeg gif webp svg bmp pdf xlsx xls docx doc pptx ppt zip mp3 mp4 mov wav"):gmatch("%S+") do
  EXTERNAL[ext] = true
end

---カーソルが乗っているリンクを返す。
---@return "wiki"|"md"|nil kind, string|nil target
local function link_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  -- wiki を先に見る（[[a]] は %b[] にも当たるので）
  for _, spec in ipairs({ { "wiki", "%[%[(.-)%]%]" }, { "md", "%b[](%b())" } }) do
    local from = 1
    while true do
      local s, e, target = line:find(spec[2], from)
      if not s then
        break
      end
      if col >= s and col <= e then
        return spec[1], target
      end
      from = e + 1
    end
  end
end

---@param kind "wiki"|"md"
---@param raw string
---@return string path, string|nil anchor
local function parse_target(kind, raw)
  local target = raw
  if kind == "wiki" then
    target = target:gsub("|.*$", "") -- [[名前|別名]]
  else
    target = vim.trim(target:sub(2, -2)) -- 外側の ( )
    target = target:gsub('%s+".*"$', ""):gsub("%s+'.*'$", "") -- (a.md "題")
    target = target:match("^<(.*)>$") or vim.uri_decode(target) -- (<a b.md>) / (a%20b.md)
  end
  local path, anchor = target:match("^(.-)#(.*)$")
  return vim.trim(path or target), anchor
end

---そのバッファの「リンクの起点」: vault の中なら vault、それ以外は git ルート、無ければファイルの隣。
local function link_root(file)
  local vault = require("config.vault")
  if vault.contains(file) then
    return vault.root()
  end
  return Snacks.git.get_root(file) or vim.fs.dirname(file)
end

local function exists(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

-- 探さないディレクトリ（node_modules 等は数が多いだけで、リンク先になることがない）
local SKIP = { [".git"] = true, [".obsidian"] = true, [".trash"] = true, node_modules = true }

---root の下から、パスの末尾が tail（/ 区切り）に一致するファイルを探す。大文字小文字は区別しない。
---@return string[]
local function search(root, tail)
  local want = "/" .. tail:lower()
  local hits = {}
  for name, kind in
    vim.fs.dir(root, {
      depth = math.huge,
      skip = function(dir)
        return not SKIP[dir]
      end,
    })
  do
    if kind == "file" and ("/" .. name:lower()):sub(-#want) == want then
      hits[#hits + 1] = vim.fs.joinpath(root, name)
    end
  end
  return hits
end

---@param kind "wiki"|"md"
---@param path string
---@param file string 今のバッファのファイル
---@return string[]
local function resolve(kind, path, file)
  path = path:gsub("\\", "/")
  local root = link_root(file)
  local names = { path }
  if vim.fn.fnamemodify(path, ":e") == "" or kind == "wiki" then
    table.insert(names, 1, path .. ".md") -- 拡張子を省いたリンク。[[a.b]] も a.b.md を先に見る
  end
  for _, name in ipairs(names) do
    -- 絶対パス → そのファイルからの相対 → ルートからの相対（/docs/a.md と vault 流の exocortex/a.md）
    local tries = { vim.fs.joinpath(vim.fs.dirname(file), name), vim.fs.joinpath(root, name) }
    if name:match("^%a:/") then
      tries = { name }
    end
    for _, try in ipairs(tries) do
      if exists(try) then
        return { vim.fs.normalize(try) }
      end
    end
  end
  -- [[名前]] はフォルダを書かないので、ツリー全体から探す
  if kind == "wiki" then
    for _, name in ipairs(names) do
      local hits = search(root, name)
      if #hits > 0 then
        return hits
      end
    end
  end
  return {}
end

-- GitHub 流の見出しアンカーに揃える: 小文字・空白は -・記号は消す（日本語は残す）
local function slug(text)
  return (text:lower():gsub("[%s]+", "-"):gsub("[!-,%./:-@%[-^`{-~]", ""))
end

---今のバッファの見出し（#見出し）かブロック（#^id）へカーソルを動かす。
local function goto_anchor(anchor)
  anchor = vim.uri_decode(anchor)
  local block = anchor:match("^%^(.+)$")
  local want = slug(anchor)
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local heading = line:match("^#+%s+(.-)%s*$")
    if (block and vim.endswith(vim.trim(line), "^" .. block)) or (not block and heading and slug(heading) == want) then
      vim.api.nvim_win_set_cursor(0, { lnum, 0 })
      return
    end
  end
  vim.notify("見出しが見つかりません: #" .. anchor, vim.log.levels.WARN)
end

local function open_file(path, anchor)
  if EXTERNAL[vim.fn.fnamemodify(path, ":e"):lower()] then
    local _, err = vim.ui.open(path)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
  if anchor and anchor ~= "" then
    goto_anchor(anchor)
  end
end

function M.markdown()
  local kind, raw = link_at_cursor()
  if not kind then
    vim.notify("カーソルの下にリンクがありません")
    return
  end
  local path, anchor = parse_target(kind, raw)
  if path:match("^%a[%w+.-]+:") and not path:match("^%a:[/\\]") then -- https: mailto: obsidian: など
    local _, err = vim.ui.open(path .. (anchor and ("#" .. anchor) or ""))
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    return
  end
  if path == "" then -- [x](#見出し) / [[#見出し]]
    goto_anchor(anchor or "")
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  local hits = resolve(kind, path, file)
  if #hits == 0 then
    vim.notify("リンク先が見つかりません: " .. path, vim.log.levels.WARN)
  elseif #hits == 1 then
    open_file(hits[1], anchor)
  else
    vim.ui.select(hits, { prompt = path }, function(choice)
      if choice then
        open_file(choice, anchor)
      end
    end)
  end
end

----------------------------------------------------
-- キーを張る
----------------------------------------------------
function M.setup()
  local group = vim.api.nvim_create_augroup("dotfiles_jump", { clear = true })
  local actions = { c = M.cpp, cpp = M.cpp, markdown = M.markdown }
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = vim.tbl_keys(actions),
    callback = function(event)
      vim.keymap.set("n", "<C-CR>", actions[event.match], { buffer = event.buf, desc = "Jump (implementation / link)" })
    end,
  })

  if vim.env.TERM_PROGRAM == "WezTerm" then
    local set_user_var = require("config.wezterm").set_user_var
    set_user_var("nvim", "1")
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        set_user_var("nvim", "")
      end,
    })
  end
end

return M
