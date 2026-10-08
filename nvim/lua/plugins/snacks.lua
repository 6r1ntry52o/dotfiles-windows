-- snacks explorer（<leader>e）でカーソルが当たっているファイルに、バッファ側
-- （config/keymaps.lua）と同じ 2 つを同じキーで効かせる。
--
-- グローバルな keymap では拾えない: explorer は buftype=nofile のバッファで、
-- バッファ側の keymap はそこを「ファイルのバッファではない」として弾く。
-- explorer の中のキーは picker 自身に登録する＝カーソル下の item がそのまま渡る。
--
-- 素で近いものはある（置き換えずに残す）: o＝explorer_open（既定アプリ＝<leader>fo 相当）、
-- y＝explorer_yank（パスを yank・ただし / 区切り）。
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      -- キーと実装を分ける（名前で参照できる action にするのが snacks の作法）
      actions = {
        reveal_in_explorer = function(_, item)
          local path = item and Snacks.picker.util.path(item)
          if path then
            require("config.winpath").reveal(path)
          end
        end,
        copy_win_path = function(_, item)
          local path = item and Snacks.picker.util.path(item)
          if path then
            require("config.winpath").copy(path)
          end
        end,
      },
      sources = {
        explorer = {
          win = {
            list = {
              keys = {
                ["<leader>fw"] = "reveal_in_explorer",
                ["<leader>fy"] = "copy_win_path",
              },
            },
          },
        },
      },
    },
  },
}
