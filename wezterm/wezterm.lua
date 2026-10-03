local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.font_size = 12.0
config.use_ime = true
config.window_background_opacity = 0.85
-- HackGen Console（未導入の PC では同梱の JetBrains Mono に落ちる）
config.font = wezterm.font_with_fallback({ "HackGen Console", "JetBrains Mono" })

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

if wezterm.target_triple:find("windows") then
  local git_bash = "C:/Program Files/Git/bin/bash.exe"
  local menu = {}

  -- PowerShell 7 があれば既定、無ければ Windows PowerShell 5.1
  -- （winget 版は MSIX＝実行エイリアス、MSI 版は Program Files に入る）
  local alias = (os.getenv("LOCALAPPDATA") or "") .. "/Microsoft/WindowsApps/pwsh.exe"
  local has_pwsh = exists("C:/Program Files/PowerShell/7/pwsh.exe") or #wezterm.glob(alias) > 0
  if has_pwsh then
    config.default_prog = { "pwsh.exe", "-NoLogo" }
    table.insert(menu, { label = "PowerShell 7", args = { "pwsh.exe", "-NoLogo" } })
  else
    config.default_prog = { "powershell.exe", "-NoLogo" }
  end
  table.insert(menu, { label = "Windows PowerShell 5.1", args = { "powershell.exe", "-NoLogo" } })
  if exists(git_bash) then
    table.insert(menu, { label = "Git Bash", args = { git_bash, "-l", "-i" } })
  end
  -- WSL は WezTerm が自動でランチャーに載せる
  config.launch_menu = menu
end

----------------------------------------------------
-- Tab
----------------------------------------------------
-- タイトルバーを非表示（終了は Alt+F4・移動はタブバーの空き部分をドラッグ）
config.window_decorations = "RESIZE"
-- タブバーの表示
config.show_tabs_in_tab_bar = true
-- タブが一つの時は非表示（false で常に表示）
config.hide_tab_bar_if_only_one_tab = false
-- falseにするとタブバーの透過が効かなくなる
-- config.use_fancy_tab_bar = false

-- タブバーの透過
config.window_frame = {
  inactive_titlebar_bg = "none",
  active_titlebar_bg = "none",
}

-- タブバーを背景色に合わせる
config.window_background_gradient = {
  colors = { "#000000" },
}

-- タブの追加ボタンを非表示
config.show_new_tab_button_in_tab_bar = false

-- タブ同士の境界線を非表示
config.colors = {
  tab_bar = {
    inactive_tab_edge = "none",
  },
}

-- タブの形をカスタマイズ
-- タブの左側の装飾
local SOLID_LEFT_ARROW = wezterm.nerdfonts.ple_lower_right_triangle
-- タブの右側の装飾
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.ple_upper_left_triangle

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
  local background = "#5c6d74"
  local foreground = "#FFFFFF"
  local edge_background = "none"
  if tab.is_active then
    background = "#ae8b2d"
    foreground = "#FFFFFF"
  end
  local edge_foreground = background
  local title = "   " .. wezterm.truncate_right(tab.active_pane.title, max_width - 1) .. "   "
  return {
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_LEFT_ARROW },
    { Background = { Color = background } },
    { Foreground = { Color = foreground } },
    { Text = title },
    { Background = { Color = edge_background } },
    { Foreground = { Color = edge_foreground } },
    { Text = SOLID_RIGHT_ARROW },
  }
end)

----------------------------------------------------
-- keybinds
----------------------------------------------------
config.disable_default_key_bindings = true
config.keys = require("keybinds").keys
config.key_tables = require("keybinds").key_tables
config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

return config
