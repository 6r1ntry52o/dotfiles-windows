-- 背景を塗らず、WezTerm の背景（黒・不透明度は wezterm/wezterm.lua）をそのまま見せる。
-- 色を二重に持たないので、WezTerm 側を変えれば Neovim も揃う。
return {
  {
    "folke/tokyonight.nvim",
    opts = {
      transparent = true,
      styles = {
        sidebars = "transparent", -- ファイルツリーなど
        floats = "transparent", -- 検索・ポップアップ
      },
    },
  },
}
