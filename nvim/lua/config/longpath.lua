-- パスが長いファイルだけ、スワップファイルと undo ファイルを作らない。
--
-- なぜ要るか: nvim はスワップ（'directory'）と undo（'undodir'）のファイル名を、`dir//` の時は
-- 元のフルパスの区切り（\ / :）を % にして作る（例: C%%Users%…%far.h.swp）。その名前が 255 文字
-- （名前 1 つの上限）を越えると、開くたびに E303（Unable to open swap file）、保存のたびに
-- E828（Cannot open undo file for writing）が出る。保存そのものは通る。
-- Windows の長いパスの設定（LongPathsEnabled）が無効な PC では、置き場を含めた全体が 259 文字を
-- 越えた所でも同じことになる（nvim.exe は longPathAware なので、有効なら全体の長さは問題ない）。
-- 2026-11-05 に nvim 0.11.6 で実測（会社のリポは 256 文字を越えるパスが多い）。
--
-- 切ると、そのファイルは落ちた時に戻せず、閉じた後の undo も残らない（切らなくても作れていない）。
-- 'directory'・'undodir' のどれか 1 つに置ければ切らない。`dir//` でない置き場（ファイル名だけで作る）は
-- 置けるとみなす。
local M = {}

---@type boolean|nil Windows の長いパスの設定が有効か（要った時に 1 回だけ調べる）
local long_paths

local function os_long_paths()
  if long_paths == nil then
    local res = vim.system({ "reg", "query", [[HKLM\SYSTEM\CurrentControlSet\Control\FileSystem]], "/v", "LongPathsEnabled" }, { text = true }):wait(3000)
    local value = res.code == 0 and (res.stdout or ""):match("LongPathsEnabled%s+REG_DWORD%s+(0x%x+)")
    long_paths = value ~= nil and tonumber(value) == 1
  end
  return long_paths
end

---full のスワップ（ext=".swp"）か undo（ext=""）を、dirs（'directory' か 'undodir'）のどれかに置けるか。
---長さは文字数で見る（Windows の上限は UTF-16 の数。サロゲートペアの文字はほぼ無いので同じとみなす）
---@param dirs string
---@param full string
---@param ext string
local function fits(dirs, full, ext)
  local name = vim.fn.strchars(full) + #ext
  for _, entry in ipairs(vim.split(dirs, ",", { trimempty = true })) do
    if not entry:match("[/\\][/\\]$") then
      return true
    end
    local dir = (vim.fn.fnamemodify((entry:gsub("[/\\]+$", "")), ":p"):gsub("[/\\]+$", ""))
    if name <= 255 and (vim.fn.strchars(dir) + 1 + name <= 259 or os_long_paths()) then
      return true
    end
  end
  return false
end

---@param buf integer
local function apply(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or vim.bo[buf].buftype ~= "" or name:match("^%a[%w+.-]+://") then
    return
  end
  local full = vim.fn.fnamemodify(name, ":p")
  if vim.bo[buf].swapfile and not fits(vim.o.directory, full, ".swp") then
    vim.bo[buf].swapfile = false
  end
  if vim.bo[buf].undofile and not fits(vim.o.undodir, full, "") then
    vim.bo[buf].undofile = false
  end
end

function M.setup()
  if vim.fn.has("win32") == 0 then
    return
  end
  -- 読み込む前に切る。スワップは BufReadPre より前に作られ、BufReadPre で切ると読み込みが崩れる
  -- （E303 は出たまま、読み取り専用になり文字コードの判定もされない＝実測）。BufNew は名前を変えた時にも来る
  vim.api.nvim_create_autocmd("BufNew", {
    group = vim.api.nvim_create_augroup("dotfiles_longpath", { clear = true }),
    callback = function(ev)
      apply(ev.buf)
    end,
  })
  -- 起動時の引数のファイルは、設定を読む前にバッファになっている（まだ読み込んでいない物だけ直す）
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.api.nvim_buf_is_loaded(buf) then
      apply(buf)
    end
  end
end

return M
