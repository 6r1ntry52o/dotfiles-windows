local wezterm = require("wezterm")
local keybinds = require("keybinds")
-- この PC だけの値（`~/.dotfiles.json`）
local machine = require("machine")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.use_ime = true

----------------------------------------------------
-- 見た目
----------------------------------------------------
local WINDOW_OPACITY = 0.97
-- ウィンドウの背景（黒）。WINDOW_OPACITY で透ける
local WINDOW_BG = "#000000"
-- タブバーは自分では塗らない＝下のウィンドウ背景がそのまま見える（本文と同じ透け方になる）
local BAR_BG = "rgba(0,0,0,0)"

-- 画面の大きさは PC ごとに違うので、`~/.dotfiles.json` の wezterm.font_size で上書きできる
config.font_size = machine.wezterm.font_size or 12.0
-- HackGen Console（未導入の PC では同梱の JetBrains Mono に落ちる）
config.font = wezterm.font_with_fallback({ "HackGen Console", "JetBrains Mono" })
config.window_background_opacity = WINDOW_OPACITY
config.window_background_gradient = {
  colors = { WINDOW_BG },
}
-- タイトルバーを非表示（終了は Alt+F4・移動はタブバーの空き部分をドラッグ）
config.window_decorations = "RESIZE"

----------------------------------------------------
-- 起動時のウィンドウの大きさ
----------------------------------------------------
-- 既定の 80x24 はテキストエディタには狭いので、画面に対する割合で出す。
-- 割合は `~/.dotfiles.json` の wezterm.window_ratio で PC ごとに変えられる
local WINDOW_RATIO = 0.8
local window_ratio = tonumber(machine.wezterm.window_ratio) or WINDOW_RATIO
if window_ratio <= 0 or window_ratio > 1 then
  -- 設定を壊さない（既定値で続ける）
  wezterm.log_error("wezterm.window_ratio が 0〜1 の外＝既定 " .. WINDOW_RATIO .. " で続ける")
  window_ratio = WINDOW_RATIO
end

-- gui-startup は起動時の最初のウィンドウだけ（2 枚目以降・新しいタブは WezTerm の既定どおり）
wezterm.on("gui-startup", function(cmd)
  local _, _, window = wezterm.mux.spawn_window(cmd or {})
  local gui = window:gui_window()
  if not gui then
    return
  end
  -- マウスがある画面＝これからウィンドウが出る画面（x/y はマルチモニタでの左上・1 枚なら 0,0）
  local screen = wezterm.gui.screens().active
  local w = math.floor(screen.width * window_ratio)
  local h = math.floor(screen.height * window_ratio)
  gui:set_inner_size(w, h)
  -- 中央寄せ
  gui:set_position(
    screen.x + math.floor((screen.width - w) / 2),
    screen.y + math.floor((screen.height - h) / 2)
  )
end)

----------------------------------------------------
-- Shell（Windows）
----------------------------------------------------
local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

-- PowerShell 7 の有無（winget 版は MSIX＝実行エイリアス、MSI 版は Program Files に入る）
local function has_pwsh()
  local alias = (os.getenv("LOCALAPPDATA") or "") .. "/Microsoft/WindowsApps/pwsh.exe"
  return exists("C:/Program Files/PowerShell/7/pwsh.exe") or #wezterm.glob(alias) > 0
end

if wezterm.target_triple:find("windows") then
  local PWSH = { "pwsh.exe", "-NoLogo" }
  local POWERSHELL = { "powershell.exe", "-NoLogo" }
  local GIT_BASH = "C:/Program Files/Git/bin/bash.exe"
  local menu = {}

  -- PowerShell 7 があれば既定、無ければ Windows PowerShell 5.1
  if has_pwsh() then
    config.default_prog = PWSH
    table.insert(menu, { label = "PowerShell 7", args = PWSH })
  else
    config.default_prog = POWERSHELL
  end
  table.insert(menu, { label = "Windows PowerShell 5.1", args = POWERSHELL })
  if exists(GIT_BASH) then
    table.insert(menu, { label = "Git Bash", args = { GIT_BASH, "-l", "-i" } })
  end
  config.launch_menu = menu

  -- WSL: ディストリは WezTerm が自動検出する（ドメイン名＝"WSL:<ディストリ名>"）。
  -- 既定だと Windows 側のフォルダで始まるので、Linux のホームで開くようにする
  local wsl_domains = wezterm.default_wsl_domains()
  for _, dom in ipairs(wsl_domains) do
    dom.default_cwd = "~"
  end
  config.wsl_domains = wsl_domains
end

----------------------------------------------------
-- Tab
----------------------------------------------------
-- アクティブなタブ＝LazyVim のタイトル（起動画面のロゴ）の青。tokyonight-moon の blue と同じ値
local TAB_ACTIVE_BG = "#82aaff"
local TAB_INACTIVE_BG = "#22272e" -- それ以外のタブ
local TAB_HOVER_BG = "#2d3440" -- マウスを載せたタブ
local TAB_ACTIVE_FG = "#1b1d2b" -- 明るい青の上なので濃色（LazyVim のステータスラインと同じ組み合わせ）
local TAB_INACTIVE_FG = "#8b949e"

local TAB_TITLE_MAX = 16
local TAB_GAP = "▏" -- U+258F（左 1/8 ブロック）。WezTerm が自前で描くのでフォントに依らない

-- タブバーの表示
config.show_tabs_in_tab_bar = true
-- タブが一つの時は非表示（false で常に表示）
config.hide_tab_bar_if_only_one_tab = false
-- retro 型のタブバー＝文字セルで描く四角いタブ（丸みなし）
-- （fancy 型は角の丸みが固定で変えられない。retro 型は×ボタンも無い）
config.use_fancy_tab_bar = false
config.show_new_tab_button_in_tab_bar = false
-- 名前＋区切りのセル 1＋右の余白 1 が収まる幅
config.tab_max_width = TAB_TITLE_MAX + 2
config.colors = {
  -- カーソル＝赤（青系の画面の中で位置を見失わないため）。重なった文字は濃色
  cursor_bg = "#ff4040",
  cursor_border = "#ff4040",
  cursor_fg = "#1b1d2b",
  tab_bar = {
    background = BAR_BG,
  },
}

-- タブに出す名前（短く）: 手で付けた名前 > 実行中のプログラム名 > ペインのタイトル
local function tab_name(tab)
  if tab.tab_title and #tab.tab_title > 0 then
    return tab.tab_title
  end
  local pane = tab.active_pane
  local proc = pane.foreground_process_name or ""
  if #proc > 0 then
    -- "C:\...\pwsh.exe" → "pwsh"
    return (proc:gsub("^.*[/\\]", ""):gsub("%.[eE][xX][eE]$", ""))
  end
  return pane.title
end

local function tab_bg(tab, hover)
  if tab.is_active then
    return TAB_ACTIVE_BG
  end
  return hover and TAB_HOVER_BG or TAB_INACTIVE_BG
end

wezterm.on("format-tab-title", function(tab, _, _, _, hover)
  local fg = tab.is_active and TAB_ACTIVE_FG or TAB_INACTIVE_FG
  local bg = tab_bg(tab, hover)
  local name = wezterm.truncate_right(tab_name(tab), TAB_TITLE_MAX)
  return {
    -- タブ間の区切り＝左端の細い縦線（セル幅の 1/8 ≒ 1px）をウィンドウの背景色で描く。
    -- retro 型は文字セル単位なので、空白 1 文字より細い隙間はこの方法で作る
    { Background = { Color = bg } },
    { Foreground = { Color = WINDOW_BG } },
    { Text = TAB_GAP },
    -- 名前（左の余白は区切りのセルが兼ねる・右に余白 1）
    { Foreground = { Color = fg } },
    { Attribute = { Intensity = tab.is_active and "Bold" or "Normal" } },
    { Text = name .. " " },
  }
end)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = keybinds.keys
config.key_tables = keybinds.key_tables
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

return config
