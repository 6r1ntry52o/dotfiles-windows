-- UTF-8 と CP932（Shift_JIS）が混ざったツリーを grep するための小物。
-- 使う側は lua/plugins/encoding.lua（<leader>sJ）。判定順は lua/config/options.lua。
--
-- 考え方: ripgrep は 1 回の実行で「ファイルごとに文字コードを見分ける」ことはできない。
--   --encoding sjis  … 全ファイルを CP932 とみなす＝UTF-8 のファイルが当たらない
--   既定（auto）     … BOM だけ見る＝BOM なし CP932 のファイルが当たらない
-- そこで文字コードの変換はさせず（--no-unicode でバイト列として照合させ）、
-- 検索語の方を「UTF-8 のバイト列 | CP932 のバイト列」の 2 択に展開する。
-- これで UTF-8・UTF-8 BOM・UTF-16（rg が BOM で変換する）・CP932 が 1 回で当たる。
-- 2026-10-05 に ripgrep 15.2.0 / Neovim 0.11（Windows）で実測。
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

-- 検索語の非 ASCII 文字だけを CP932 のバイト列（\xNN）に置き換える。
-- ASCII はそのまま残すので、正規表現のメタ文字は置き換えた側でも効く
-- （CP932 は 1 バイト目が 0x81 以上＝ASCII と衝突しない）。
-- CP932 に無い文字（絵文字など）が混ざっていたら nil。
---@param pat string
---@return string?
function M.as_cp932_bytes(pat)
  local out = {}
  for ch in pat:gmatch("[\1-\127\194-\244][\128-\191]*") do
    if #ch == 1 then
      out[#out + 1] = ch
    else
      local sjis = vim.iconv(ch, "utf-8", "cp932")
      -- CP932 に無い文字は、失敗ではなく "?" に潰れて返ってくる（絵文字など）。
      -- そのまま展開すると "?" を探すことになるので、ここで諦める
      -- （CP932 のファイルにその文字は入れられない＝探す意味がない）。
      if not sjis or sjis == "" or sjis:match("^%?+$") then
        return nil
      end
      out[#out + 1] = (sjis:gsub(".", function(b)
        return ("\\x%02x"):format(b:byte())
      end))
    end
  end
  return table.concat(out)
end

-- 検索語を「UTF-8 | CP932」の 2 択に展開する。ASCII だけなら触らない
-- （ASCII は CP932 のファイルでもバイト列が同じなので、そのままで当たる）。
-- snacks の `検索語 -- rg の引数` という書き方は壊さない。
---@param search string
---@return string
function M.dual_pattern(search)
  local head, tail = search:match("^(.-)%s+%-%-%s*(.*)$")
  local pat = head or search
  if pat == "" then
    return search
  end
  local alt = M.as_cp932_bytes(pat)
  if not alt or alt == pat then
    return search
  end
  local dual = "(?:" .. pat .. "|" .. alt .. ")"
  return head and (dual .. " -- " .. tail) or dual
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
-- ので CP932 と決め打つ＝sJ で探しているのは UTF-8 と CP932 の混在ツリー）。
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

-- 既定のファイルプレビュー＋上の直し。picker の `preview` に渡す。
-- 全部の picker に効かせたくなったら opts.picker.previewers ではなく
-- `Snacks.picker.preview.file` を差し替える必要があるので、ここでは sJ 専用のまま
-- （latin1 の実ファイルまで CP932 とみなして潰すのを避ける）。
---@param ctx snacks.picker.preview.ctx
function M.preview(ctx)
  local ret = Snacks.picker.preview.file(ctx)
  if fix_buf(ctx) then
    -- 行を入れ替えた＝カーソル位置と一致の強調を貼り直す
    ctx.preview:loc()
  end
  return ret
end

return M
