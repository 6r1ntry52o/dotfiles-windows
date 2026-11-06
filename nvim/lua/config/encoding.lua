-- UTF-8 と CP932（Shift_JIS）が混ざったツリーを grep するための小物。
-- 使う側は lua/plugins/encoding.lua（既定の grep の picker に M.grep を足す）。判定順は lua/config/options.lua。
--
-- 考え方: ripgrep は 1 回の実行で「ファイルごとに文字コードを見分ける」ことはできない。
--   --encoding sjis  … 全ファイルを CP932 とみなす＝UTF-8 のファイルが当たらない
--   既定（auto）     … BOM だけ見る＝BOM なし CP932 のファイルが当たらない
-- そこで文字コードの変換はさせず、検索語の方を「UTF-8 の文字 | CP932 のバイト列」の 2 択に展開する。
-- CP932 の側だけを (?-u:…) に入れてバイト列として照合させる（UTF-8 の側の正規表現の意味は変えない）。
-- これで UTF-8・UTF-8 BOM・UTF-16（rg が BOM で変換する）・CP932 が 1 回で当たる。
-- 2026-10-05 に ripgrep 15.2.0 / Neovim 0.11（Windows）で実測。2026-11-06 に --no-unicode（全体）から
-- (?-u:…)（CP932 の側だけ）に替えた。
--
-- 検索するのは元のファイル。clangd 用の UTF-8 の写し（config/utf8_mirror.lua）は使わない。
local M = {}

-- 厳密な UTF-8 判定。vim.iconv は判定に使えない（utf-8 → utf-8 は正しい文字列でも
-- nil、utf-16le へは不正なバイト列でも黙って変換する＝どちらも成否が信用できない）ので
-- 自分で先頭バイトと後続バイトを見る。
---@param s string
---@return boolean
function M.is_utf8(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len ---@type number
    if c < 0x80 then
      len = 1
    elseif c >= 0xc2 and c <= 0xdf then
      len = 2
    elseif c >= 0xe0 and c <= 0xef then
      len = 3
    elseif c >= 0xf0 and c <= 0xf4 then
      len = 4
    else
      return false -- 先頭になれないバイト（CP932 の 2 バイト目など）
    end
    for j = i + 1, i + len - 1 do
      local b = s:byte(j)
      if not b or b < 0x80 or b > 0xbf then
        return false
      end
    end
    i = i + len
  end
  return true
end

-- CP932 のバイト列を UTF-8 に直す。UTF-8 ならそのまま返す。
-- 行が途中で切れていて 2 バイト目が無いバイト列が混ざっていても（snacks のプレビューは
-- 長い行を 500 バイトで切る）、Windows の iconv はそこだけ "?" にして残りを返す
-- （nil にはならない＝2026-10-07 実測）。
---@param s string
---@return string text, boolean converted
function M.to_utf8(s)
  if M.is_utf8(s) then
    return s, false
  end
  local out = vim.iconv(s, "cp932", "utf-8")
  if not out then
    return s, false
  end
  return out, true
end

-- 検索語の非 ASCII 文字だけを CP932 のバイト列（\xNN）に置き換える（dual_pattern が (?-u:…) に入れる）。
-- ASCII はそのまま残すので、正規表現のメタ文字は置き換えた側でも効く
-- （CP932 は 1 バイト目が 0x81 以上＝ASCII と衝突しない）。
-- 1 文字ずつ (?-i:…) で囲む: 「表+」の + が文字全体に掛かるように、また大文字小文字を無視する時に
-- 2 バイト目の A〜Z・a〜z が入れ替わって別の文字に当たらないように（「ア」83 41 が「ャ」83 61 にも当たる）。
-- […] の中は ( ) を書けないのでバイトを並べるだけ。
-- CP932 に無い文字（絵文字など）が混ざっていたら nil。
---@param pat string
---@return string?
function M.as_cp932_bytes(pat)
  local out = {}
  local depth, escaped, first = 0, false, false -- […] の深さ・直前が \・[ か [^ の直後
  for ch in pat:gmatch("[\1-\127\194-\244][\128-\191]*") do
    local opened = false
    if #ch == 1 then
      out[#out + 1] = ch
      if escaped then
        escaped = false
      elseif ch == "\\" then
        escaped = true
      elseif ch == "[" then
        depth, opened = depth + 1, true
      elseif ch == "]" and depth > 0 and not first then
        depth = depth - 1
      end
    else
      local sjis = vim.iconv(ch, "utf-8", "cp932")
      -- CP932 に無い文字は、失敗ではなく "?" に潰れて返ってくる（絵文字など）。
      -- そのまま展開すると "?" を探すことになるので、ここで諦める
      -- （CP932 のファイルにその文字は入れられない＝探す意味がない）。
      if not sjis or sjis == "" or sjis:match("^%?+$") then
        return nil
      end
      local bytes = sjis:gsub(".", function(b)
        return ("\\x%02x"):format(b:byte())
      end)
      out[#out + 1] = depth > 0 and bytes or ("(?-i:" .. bytes .. ")")
      escaped = false
    end
    -- [ と [^ の直後の ] は文字そのもの
    first = opened or (first and ch == "^")
  end
  return table.concat(out)
end

-- 正規表現の記号を文字そのものにする（rg の regex::escape と同じ記号）
local function escape(s)
  return (s:gsub("[\\%.%+%*%?%(%)|%[%]{}%^%$#&%-~]", "\\%0"))
end

-- rg の smart-case は \x41 などのバイトも大文字に数える（実測）。2 バイト目が A〜Z の文字が入ると
-- 検索語全体が大文字小文字を区別し、UTF-8 のファイルでも「hyouji表示」が「Hyouji表示」に当たらなくなる。
-- 打った検索語（\ の後の 1 文字は除く）に大文字が無く、rg の引数で大文字小文字を指定していなければ、
-- (?i:…) で smart-case と同じにする
---@param pat string
---@param tail string?
local function ignore_case(pat, tail)
  if pat:gsub("\\.", ""):find("%u") then
    return false
  end
  for _, a in ipairs(vim.split(tail or "", "%s+", { trimempty = true })) do
    if a == "-s" or a == "-i" or a == "-S" or a:match("^%-%-.*case") then
      return false
    end
  end
  return true
end

-- 検索語を「UTF-8 | CP932」の 2 択に展開する。ASCII だけなら触らない
-- （ASCII は CP932 のファイルでもバイト列が同じなので、そのままで当たる）。
-- snacks の `検索語 -- rg の引数` という書き方は壊さない。
-- fixed（文字そのもので探す＝snacks が --fixed-strings を付ける。sw と <a-r> で切り替えた時）は、
-- 記号を逃がした正規表現にして、--no-fixed-strings を足す（後ろの引数が勝つ）。
-- \p{…} があれば展開しない（(?-u:…) の中では書けず、rg が止まる＝UTF-8 のファイルにも当たらなくなる）。
---@param search string
---@param fixed? boolean
---@return string
function M.dual_pattern(search, fixed)
  local head, tail = search:match("^(.-)%s+%-%-%s*(.*)$")
  local pat = head or search
  if not pat:find("[\128-\255]") or (not fixed and pat:find("\\[pP]")) then
    return search
  end
  if fixed then
    pat = escape(pat)
  end
  local alt = M.as_cp932_bytes(pat)
  if not alt then
    return search
  end
  local dual = (ignore_case(pat, tail) and "(?i:" or "(?:") .. pat .. "|(?-u:" .. alt .. "))"
  if fixed then
    tail = (tail and tail ~= "" and (tail .. " ") or "") .. "--no-fixed-strings"
  end
  return tail and (dual .. " -- " .. tail) or dual
end

-- 一覧に出す前に、CP932 のまま出てきた行を UTF-8 へ直す。
-- rg の出力は（変換させていないので）CP932 のファイルでは CP932 のバイト列のまま。
-- 列番号もバイト位置なので、UTF-8 に直した後の位置へ読み替える（飛んだ先のカーソルがずれる）。
---@param item snacks.picker.finder.Item
function M.fix_item(item)
  local file = item.file
  if type(file) ~= "string" or type(item.text) ~= "string" then
    return
  end
  -- grep の item.text は "ファイル:行:列:本文"（ファイル名に : を含むので長さで切る）
  local lnum, col, text = item.text:sub(#file + 2):match("^(%d+):(%d+):(.*)$")
  if not text or M.is_utf8(text) then
    return
  end
  local fixed = vim.iconv(text, "cp932", "utf-8")
  if not fixed then
    return
  end
  local before = vim.iconv(text:sub(1, tonumber(col) - 1), "cp932", "utf-8")
  local newcol = before and (#before + 1) or tonumber(col)
  item.text = ("%s:%s:%d:%s"):format(file, lnum, newcol, fixed)
  item.pos = { tonumber(lnum), newcol - 1 }
  local resolve = item.resolve
  item.resolve = function()
    if resolve then
      resolve()
    end
    -- 一致位置の強調もバイト位置でずれるので、直した行では付けない（誤った強調より無印）
    item.positions, item.end_pos = nil, nil
    item.line = M.to_utf8(item.line or text)
  end
end

-- プレビュー（picker の右側）の文字化け対策。
-- snacks のファイルプレビューは io.open で生のバイト列を読んで buffer に流し込む＝
-- nvim の 'fileencodings' を通らないので、CP932 のファイルは必ず化ける
-- （一覧は fix_item で直るが、プレビューは別経路）。grep の一致行が ASCII だけでも
-- 周りの日本語コメントが化けるため、プレビューは行単位ではなく buffer 全体を見る。
--
-- 既定のプレビューを走らせた後、UTF-8 でない行だけ直す（元の文字コードは分からない
-- ので CP932 と決め打つ＝このリポで UTF-8 でないテキストは CP932）。
---@param ctx snacks.picker.preview.ctx
local function fix_buf(ctx)
  local buf = ctx.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end
  -- 実ファイルの buffer は触らない（名前がある＝nvim が 'fileencodings' で開いた物）。
  -- プレビュー用の scratch だけを書き換える＝麟太郎が編集中の buffer を壊さない。
  if buf == ctx.item.buf or vim.api.nvim_buf_get_name(buf) ~= "" then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local hit = false
  for i, line in ipairs(lines) do
    if not M.is_utf8(line) then
      local fixed, converted = M.to_utf8(line)
      if converted then
        lines[i], hit = fixed, true
      end
    end
  end
  if not hit then
    return false
  end
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = modifiable
  return true
end

-- 既定のファイルプレビュー＋上の直し。picker 全体の `preview`（自分のプレビューを持たない
-- source＝ファイル・explorer・grep・LSP の参照・quickfix など）に入れる（plugins/encoding.lua）。
-- latin1 の実ファイルも CP932 とみなして直すが、この PC で UTF-8 でないテキストは CP932 なので構わない。
---@param ctx snacks.picker.preview.ctx
function M.preview(ctx)
  local ret = Snacks.picker.preview.file(ctx)
  if fix_buf(ctx) then
    -- 行を入れ替えた＝カーソル位置と一致の強調を貼り直す
    ctx.preview:loc()
  end
  return ret
end

---@param text string
local function lines_to_utf8(text)
  local lines = vim.split(text, "\n", { plain = true })
  for i, line in ipairs(lines) do
    lines[i] = M.to_utf8(line)
  end
  return table.concat(lines, "\n")
end

-- git の差分の hunk の一覧（<leader>gd）のプレビュー。hunk の本文（item.diff）は CP932 のまま持つ:
-- <Tab> のステージは item.diff をそのまま git apply --cached に渡すので、直すと UTF-8 の行が
-- CP932 のファイルの index に入る。見せる間だけ UTF-8 にした物に差し替える（プレビューは差し替えた
-- 物をその場で読む。fancy・syntax・terminal のどれも）
---@param ctx snacks.picker.preview.ctx
function M.diff_preview(ctx)
  local raw = ctx.item.diff
  if type(raw) ~= "string" or M.is_utf8(raw) then
    return Snacks.picker.preview.diff(ctx)
  end
  ctx.item.diff = lines_to_utf8(raw)
  local ok, ret = pcall(Snacks.picker.preview.diff, ctx)
  ctx.item.diff = raw
  if not ok then
    error(ret)
  end
  return ret
end

-- grep の picker（grep・grep_word・grep_buffers）の設定に足す分。
-- 検索語を 2 択に展開し、CP932 のまま出てきた行を UTF-8 に直す（右のプレビューは M.preview）
M.grep = {
  filter = {
    transform = function(picker, filter)
      filter.search = M.dual_pattern(filter.search, picker.opts.regex == false)
    end,
  },
  transform = M.fix_item,
}

return M
