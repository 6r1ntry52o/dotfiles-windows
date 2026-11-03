-- snacks explorer（<leader>e）でカーソルが当たっているファイルに、バッファ側
-- （config/keymaps.lua）と同じ 2 つを同じキーで効かせる。
--
-- グローバルな keymap では拾えない: explorer は buftype=nofile のバッファで、
-- バッファ側の keymap はそこを「ファイルのバッファではない」として弾く。
-- explorer の中のキーは picker 自身に登録する＝カーソル下の item がそのまま渡る。
--
-- 素で近いものはある（置き換えずに残す）: o＝explorer_open（既定アプリ＝<leader>fo 相当）、
-- y＝explorer_yank（パスを yank・ただし / 区切り）。
--
-- grep・ファイル検索と TUI（lazygit・lazymsbuild）は全幅で開き、上下は MARGIN 行ずつ空ける。
-- 下の余白は statusline と cmdline の上に取る＝開いている間も statusline が見える。

local MARGIN = 2

-- statusline と cmdline の行数。LazyVim は laststatus=3（statusline 1 行）・cmdheight=1。
local function rows_below()
  return vim.o.cmdheight + (vim.o.laststatus == 0 and 0 or 1)
end

-- 開くたび（と画面のリサイズのたび）に計算する。
local function height()
  return vim.o.lines - rows_below() - 2 * MARGIN
end

return {
  "folke/snacks.nvim",
  opts = {
    -- row（上の余白）を float に入れないのは、そこは blame_line・scratch・通知の履歴など
    -- 自分の大きさを持つフロートにも効いて、中央から上に寄せてしまうため。大きさだけなら
    -- それらは自分の値が勝つ。row は terminal 側＝フロートのターミナル（lazygit・lazymsbuild・
    -- git blame の表示）にだけ置く。右ペインのターミナル（config/keymaps.lua）は split で、
    -- row も float の大きさも使わない。
    -- lazymsbuild はここで決める: plugins/lazymsbuild.lua は upstream の
    -- docs/editors/lazyvim.md と同じ中身に保つので、そちらに win を足さない。
    styles = {
      float = { width = 0, height = height },
      terminal = { row = MARGIN },
    },
    picker = {
      -- 既定の preset は幅 120 桁を境に default と vertical を切り替えるので両方広げる。
      -- ivy（<leader>sb）・vscode・select は元から小さく開くための形なので残す。
      layouts = {
        default = { layout = { width = 0, height = height, row = MARGIN } },
        vertical = { layout = { width = 0, height = height, row = MARGIN } },
      },
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
