-- 呼び出しの階層をツリーで出す（gaI＝呼び出し元・gaO＝呼び出し先。キーは plugins/call_tree.lua）。
-- LazyVim の gai / gao（snacks）は 1 段だけの一覧で、上へたどるには飛んでもう一度押すしかない。
-- ここではカーソルの関数を根にした木を下の窓に出し、節を開くたびに次の段を LSP に聞く
-- （全部を先に聞くと、よく呼ばれる関数では件数が爆発する）。
--
-- 窓の中のキー:
--   l / <Tab>  開く（<Tab> は開閉）   h  閉じる（閉じていれば親へ）
--   L          その下を全部開く（深さ MAX_DEPTH 段・MAX_NODES 件まで）
--   <CR>       呼んでいる場所へ飛ぶ（根は関数そのもの）   p  窓に残ったまま見る   q  閉じる
-- 印: ▸ 閉じている  ▾ 開いている  · その先が無い  ↻ 祖先と同じ関数（再帰。開かない）
--
-- clangd は別のファイルからの呼び出しをインデックスから引く。compile_commands.json に無い
-- ファイルや、裏のインデックス作りが終わる前は、同じファイルの中の呼び出ししか出ない。
local M = {}

local MAX_DEPTH = 8
local MAX_NODES = 300

local ns = vim.api.nvim_create_namespace("dotfiles_call_tree")

---@class dotfiles.CallNode
---@field item lsp.CallHierarchyItem
---@field site {uri: string, ranges: lsp.Range[]} 呼んでいる場所（根は関数そのもの）
---@field depth integer
---@field parent? dotfiles.CallNode
---@field children? dotfiles.CallNode[] nil＝まだ聞いていない
---@field open? boolean
---@field loading? fun()[] 返事待ちの間だけある（答えを待っている done）
---@field cycle? boolean

---@class dotfiles.CallTree
---@field dir "incoming"|"outgoing"
---@field client_id integer
---@field src_buf integer
---@field src_win integer
---@field buf integer
---@field win integer
---@field root dotfiles.CallNode
---@field rows dotfiles.CallNode[] 行番号 → 節
---@field cache table<string, lsp.CallHierarchyIncomingCall[]|lsp.CallHierarchyOutgoingCall[]>

---@type table<integer, dotfiles.CallTree>
local trees = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "呼び出しの階層" })
end

---@param item lsp.CallHierarchyItem
local function id_of(item)
  local pos = item.selectionRange.start
  return ("%s:%d:%d"):format(item.uri, pos.line, pos.character)
end

---@param node dotfiles.CallNode
local function is_cycle(node)
  local id = id_of(node.item)
  local up = node.parent
  while up do
    if id_of(up.item) == id then
      return true
    end
    up = up.parent
  end
  return false
end

---@param node dotfiles.CallNode
local function mark_of(node)
  if node.cycle then
    return "↻"
  elseif node.loading then
    return "…"
  elseif node.children and #node.children == 0 then
    return "·"
  end
  return node.open and "▾" or "▸"
end

---@param tree dotfiles.CallTree
local function render(tree)
  if not vim.api.nvim_buf_is_valid(tree.buf) then
    return
  end
  local cursor_node
  if vim.api.nvim_win_is_valid(tree.win) and vim.api.nvim_win_get_buf(tree.win) == tree.buf then
    cursor_node = tree.rows[vim.api.nvim_win_get_cursor(tree.win)[1]]
  end

  local lines, marks, rows = {}, {}, {}
  ---@param node dotfiles.CallNode
  local function add(node)
    local indent = string.rep("  ", node.depth)
    local mark = mark_of(node)
    local name = node.item.detail ~= nil and node.item.detail ~= "" and node.item.detail or node.item.name
    local count = #node.site.ranges > 1 and (" ×%d"):format(#node.site.ranges) or ""
    local pos = (node.site.ranges[1] or node.item.selectionRange).start
    local where = ("%s:%d"):format(vim.fs.basename(vim.uri_to_fname(node.site.uri)), pos.line + 1)
    local head = indent .. mark .. " "
    local line = head .. name .. count .. "  " .. where
    lines[#lines + 1] = line
    rows[#rows + 1] = node
    local row = #lines - 1
    marks[#marks + 1] = { row, #indent, #head, node.cycle and "DiagnosticWarn" or "Special" }
    marks[#marks + 1] = { row, #head, #head + #name, "Function" }
    marks[#marks + 1] = { row, #line - #where, #line, "Comment" }
    if node.open and node.children and not node.cycle then
      for _, child in ipairs(node.children) do
        add(child)
      end
    end
  end
  add(tree.root)
  tree.rows = rows

  vim.bo[tree.buf].modifiable = true
  vim.api.nvim_buf_set_lines(tree.buf, 0, -1, false, lines)
  vim.bo[tree.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(tree.buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(tree.buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end

  if cursor_node and vim.api.nvim_win_is_valid(tree.win) then
    for row, node in ipairs(rows) do
      if node == cursor_node then
        vim.api.nvim_win_set_cursor(tree.win, { row, 0 })
        break
      end
    end
  end
end

---node の次の段を聞いて children を埋める。同じ関数の答えは使い回す（ひし形に呼ばれる時）。
---@param tree dotfiles.CallTree
---@param node dotfiles.CallNode
---@param done fun()
local function fetch(tree, node, done)
  if node.children then
    return done()
  elseif node.loading then
    table.insert(node.loading, done)
    return
  end

  local function fill(calls)
    node.children = {}
    for _, call in ipairs(calls) do
      local item = tree.dir == "incoming" and call.from or call.to
      ---@type dotfiles.CallNode
      local child = {
        item = item,
        -- incoming の fromRanges は呼び出し元（from）の中、outgoing の fromRanges は node の中
        site = { uri = tree.dir == "incoming" and item.uri or node.item.uri, ranges = call.fromRanges or {} },
        depth = node.depth + 1,
        parent = node,
      }
      child.cycle = is_cycle(child)
      node.children[#node.children + 1] = child
    end
    table.sort(node.children, function(a, b)
      if a.site.uri ~= b.site.uri then
        return a.site.uri < b.site.uri
      end
      local pa = (a.site.ranges[1] or a.item.selectionRange).start
      local pb = (b.site.ranges[1] or b.item.selectionRange).start
      if pa.line ~= pb.line then
        return pa.line < pb.line
      end
      return pa.character < pb.character
    end)
  end

  local key = id_of(node.item)
  if tree.cache[key] then
    fill(tree.cache[key])
    return done()
  end
  local client = vim.lsp.get_client_by_id(tree.client_id)
  if not client then
    node.children = {}
    notify("LSP が止まっています", vim.log.levels.WARN)
    return done()
  end
  node.loading = { done }
  local function finish(calls)
    local waiting = node.loading or {}
    node.loading = nil
    fill(calls)
    for _, fn in ipairs(waiting) do
      fn()
    end
  end
  local method = tree.dir == "incoming" and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
  local bufnr = vim.api.nvim_buf_is_valid(tree.src_buf) and tree.src_buf or nil
  local sent = client:request(method, { item = node.item }, function(err, result)
    if err then
      notify(("%s: %s"):format(node.item.name, err.message), vim.log.levels.WARN)
    end
    tree.cache[key] = result or {}
    finish(tree.cache[key])
  end, bufnr)
  if not sent then
    notify("LSP に送れませんでした", vim.log.levels.WARN)
    finish({})
  end
end

---@param tree dotfiles.CallTree
local function current(tree)
  return tree.rows[vim.api.nvim_win_get_cursor(0)[1]]
end

---@param tree dotfiles.CallTree
---@param node dotfiles.CallNode
local function expand(tree, node)
  if node.cycle then
    return notify(node.item.name .. " は上の段と同じ関数（再帰）")
  end
  node.open = true
  fetch(tree, node, function()
    render(tree)
  end)
  render(tree)
end

---node の下を深さ MAX_DEPTH 段・MAX_NODES 件まで全部開く。
---@param tree dotfiles.CallTree
---@param node dotfiles.CallNode
local function expand_all(tree, node)
  -- walking: 答えが使い回しだと fetch の done はその場で呼ばれる。たどり終える前に
  -- 「止めた」を出さないための目印
  local budget, pending, cut, walking = MAX_NODES, 0, false, true
  local function finish()
    render(tree)
    if cut then
      notify(("%d 段・%d 件で止めた（先は l で開く）"):format(MAX_DEPTH, MAX_NODES))
    end
  end
  ---@param n dotfiles.CallNode
  local function visit(n)
    if n.cycle then
      return
    end
    if n.depth - node.depth >= MAX_DEPTH or budget <= 0 then
      cut = cut or n.children == nil or #n.children > 0
      return
    end
    n.open = true
    if n.children then
      budget = budget - #n.children
      for _, child in ipairs(n.children) do
        visit(child)
      end
      return
    end
    pending = pending + 1
    fetch(tree, n, function()
      pending = pending - 1
      budget = budget - #n.children
      for _, child in ipairs(n.children) do
        visit(child)
      end
      if pending > 0 or walking then
        render(tree)
      else
        finish()
      end
    end)
  end
  visit(node)
  walking = false
  if pending == 0 then
    finish()
  else
    render(tree)
  end
end

---@param tree dotfiles.CallTree
---@param stay boolean 窓に残る（p）
local function jump(tree, stay)
  local node = current(tree)
  local client = vim.lsp.get_client_by_id(tree.client_id)
  if not node or not client then
    return
  end
  local range = node.site.ranges[1] or node.item.selectionRange
  if not vim.api.nvim_win_is_valid(tree.src_win) then
    vim.cmd("aboveleft split")
    tree.src_win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_set_current_win(tree.src_win)
  vim.lsp.util.show_document({ uri = node.site.uri, range = range }, client.offset_encoding, { focus = true })
  if stay then
    vim.api.nvim_set_current_win(tree.win)
  end
end

---@param tree dotfiles.CallTree
local function set_keys(tree)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = tree.buf, nowait = true, desc = desc })
  end
  map("l", function()
    local node = current(tree)
    if node then
      expand(tree, node)
    end
  end, "開く")
  map("<Tab>", function()
    local node = current(tree)
    if node and node.open then
      node.open = false
      render(tree)
    elseif node then
      expand(tree, node)
    end
  end, "開閉")
  map("h", function()
    local node = current(tree)
    if not node then
      return
    end
    if node.open and node.children and #node.children > 0 then
      node.open = false
      render(tree)
    elseif node.parent then
      for row, n in ipairs(tree.rows) do
        if n == node.parent then
          vim.api.nvim_win_set_cursor(0, { row, 0 })
          break
        end
      end
    end
  end, "閉じる / 親へ")
  map("L", function()
    local node = current(tree)
    if node then
      expand_all(tree, node)
    end
  end, "下を全部開く")
  map("<CR>", function()
    jump(tree, false)
  end, "呼んでいる場所へ")
  map("p", function()
    jump(tree, true)
  end, "見る（窓に残る）")
  map("q", function()
    vim.api.nvim_win_close(tree.win, true)
  end, "閉じる")
end

---下に窓を開く（前に開いた木の窓があれば使い回す）。
---@return integer win
local function tree_window()
  for _, tree in pairs(trees) do
    if vim.api.nvim_win_is_valid(tree.win) and vim.api.nvim_win_get_tabpage(tree.win) == vim.api.nvim_get_current_tabpage() then
      return tree.win
    end
  end
  vim.cmd("botright " .. math.max(8, math.floor(vim.o.lines / 3)) .. "split")
  local win = vim.api.nvim_get_current_win()
  for opt, value in pairs({
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    wrap = false,
    list = false,
    spell = false,
    cursorline = true,
    winfixheight = true,
  }) do
    vim.wo[win][opt] = value
  end
  return win
end

---@param dir "incoming"|"outgoing"
function M.open(dir)
  local method = dir == "incoming" and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
  local src_buf = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = src_buf, method = method })[1]
  if not client then
    return notify("呼び出しの階層を返せる LSP が付いていません（:LspInfo で確認）", vim.log.levels.WARN)
  end
  if client.name == "clangd" and require("config.clangd_profile").fallback(vim.api.nvim_buf_get_name(src_buf)) then
    notify(
      "このファイルは compile_commands.json に無い（clangd は推測のフラグで解析中）。別のファイルからの呼び出しは出ない。:CompileCommands で作る",
      vim.log.levels.WARN
    )
  end
  local src_win = vim.api.nvim_get_current_win()
  local params = vim.lsp.util.make_position_params(src_win, client.offset_encoding)
  client:request("textDocument/prepareCallHierarchy", params, function(err, result)
    if err then
      return notify(err.message, vim.log.levels.WARN)
    end
    local item = result and result[1]
    if not item then
      return notify("カーソルの下に関数がありません")
    end

    local win = tree_window()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "dotfiles_call_tree"
    vim.api.nvim_win_set_buf(win, buf)
    vim.wo[win].winbar = (dir == "incoming" and "呼び出し元: " or "呼び出し先: ") .. item.name
    ---@type dotfiles.CallTree
    local tree = {
      dir = dir,
      client_id = client.id,
      src_buf = src_buf,
      src_win = src_win,
      buf = buf,
      win = win,
      root = { item = item, site = { uri = item.uri, ranges = {} }, depth = 0 },
      rows = {},
      cache = {},
    }
    trees[buf] = tree
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        trees[buf] = nil
      end,
    })
    set_keys(tree)
    expand(tree, tree.root)
  end, src_buf)
end

return M
