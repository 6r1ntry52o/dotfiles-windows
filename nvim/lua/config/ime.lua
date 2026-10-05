-- INSERT 以外のモードでは IME（このPCは Google 日本語入力）を必ず OFF にする。
-- Esc で戻った直後に IME が ON のままだと、h/j/k/l や dd が IME に食われて
-- 「ひじくる」のような未確定文字になる＝ノーマルモードのキーが1つも通らない。
--
-- 仕組み: Windows の IME の ON/OFF は「ウィンドウごと」に持たれていて、外から
-- メッセージで切り替えられる。
--   GetForegroundWindow()  … 今フォーカスされているウィンドウ（nvim を使っている間は WezTerm）
--   ImmGetDefaultIMEWnd()  … そのウィンドウのスレッドが持つ IME 用の隠しウィンドウ
--   WM_IME_CONTROL         … その隠しウィンドウへ「状態を取れ/変えろ」を送る
-- zenhan.exe がやっているのと同じ手順を、LuaJIT の FFI から直接叩く。
-- Esc のたびに exe を起動しないので、体感の遅れもプロセスの散らかりも無い。
--
-- 2026-10-05 に Windows 11 (26300) / WezTerm / Google 日本語入力で、
-- WezTerm と Obsidian の両方のウィンドウに効くことを実測して採用した。
-- 注意: nvim 本体ではなく「前面のウィンドウ」を対象にするので、フォーカスが
-- 外れている間は触らない（別のアプリの IME を勝手に消さないため）。
local M = {}

local ffi_ok, ffi = pcall(require, "ffi")
-- Windows の nvim（LuaJIT）でだけ動く。WSL や Linux 側の nvim では何もしない
-- （そちらは IME が X/Wayland 側の持ち物で、この手では触れない）。
local supported = ffi_ok and jit ~= nil and jit.os == "Windows"

local user32, imm32

local WM_IME_CONTROL = 0x0283
local IMC_GETOPENSTATUS = 0x0005
local IMC_SETOPENSTATUS = 0x0006
-- 相手（WezTerm）が固まっていたら待たずに諦める。SendMessage で素直に待つと
-- 相手の描画が詰まっている間 nvim ごと止まる。
local SMTO_ABORTIFHUNG = 0x0002
local TIMEOUT_MS = 100

if supported then
  -- 同じ型を二度宣言すると cdef が error を投げる（設定の再読み込み時）ので pcall で包む
  pcall(ffi.cdef, [[
    typedef void* HWND;
    HWND GetForegroundWindow(void);
    HWND ImmGetDefaultIMEWnd(HWND hWnd);
    intptr_t SendMessageTimeoutW(HWND hWnd, unsigned int Msg, uintptr_t wParam, intptr_t lParam,
                                 unsigned int fuFlags, unsigned int uTimeout, uintptr_t *lpdwResult);
  ]])
  local ok_u, u = pcall(ffi.load, "user32")
  local ok_i, i = pcall(ffi.load, "imm32")
  if ok_u and ok_i then
    user32, imm32 = u, i
  else
    supported = false
  end
end

-- フォーカスを失っている間は前面のウィンドウが別アプリ＝触らない。
-- 既定を true にしているのは、起動直後や headless では FocusGained が来ないため。
local focused = true

---@param sub integer IMC_GETOPENSTATUS か IMC_SETOPENSTATUS
---@param value integer
---@return integer? status 取得できた時だけ 0(OFF)/1(ON)
local function control(sub, value)
  if not supported then
    return nil
  end
  local hwnd = user32.GetForegroundWindow()
  if hwnd == nil then
    return nil
  end
  local ime = imm32.ImmGetDefaultIMEWnd(hwnd)
  if ime == nil then
    return nil -- IME を持たないウィンドウ
  end
  local out = ffi.new("uintptr_t[1]")
  local rc = user32.SendMessageTimeoutW(ime, WM_IME_CONTROL, sub, value, SMTO_ABORTIFHUNG, TIMEOUT_MS, out)
  if rc == 0 then
    return nil -- 時間切れ・相手が応答しない
  end
  return tonumber(out[0])
end

--- 今フォーカスされているウィンドウの IME 状態。0=OFF・1=ON・nil=取れなかった
function M.status()
  return control(IMC_GETOPENSTATUS, 0)
end

--- IME を OFF にする（既に OFF なら何も起きない）
function M.off()
  if not focused then
    return
  end
  control(IMC_SETOPENSTATUS, 0)
end

function M.setup()
  if not supported then
    return
  end
  local group = vim.api.nvim_create_augroup("ime_off_outside_insert", { clear = true })

  -- INSERT を抜けた時。コマンドライン（/ で日本語を検索した後など）と
  -- :terminal の入力モードを抜けた時も、戻り先はノーマルモードなので同じ扱い。
  vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave", "TermLeave" }, {
    group = group,
    callback = function()
      M.off()
    end,
    desc = "IME を OFF にする（INSERT 以外では常に OFF）",
  })

  -- 起動時（ノーマルモードで始まる）。前のアプリで ON だった状態を引き継がない
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      M.off()
    end,
    desc = "起動時に IME を OFF にする",
  })

  -- 他のアプリから戻ってきた時。INSERT 中（と :terminal の入力中）に離席した場合は
  -- そのまま日本語を続けられるよう、モードを見てから消す。
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      focused = true
      -- i / ic / ix（挿入）と t（ターミナル）は打っている最中＝触らない
      if not vim.fn.mode():match("^[it]") then
        M.off()
      end
    end,
    desc = "復帰時、INSERT 以外なら IME を OFF にする",
  })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      focused = false
    end,
  })

  -- 効いているか確かめる用。0=OFF・1=ON
  vim.api.nvim_create_user_command("ImeState", function()
    local s = M.status()
    local label = s == 1 and "ON" or (s == 0 and "OFF" or "取得できない")
    vim.notify("IME: " .. label, s == nil and vim.log.levels.WARN or vim.log.levels.INFO)
  end, { desc = "前面ウィンドウの IME の状態を表示する" })
end

return M
