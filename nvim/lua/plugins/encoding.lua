-- 文字コードまわりのうち、プラグインに関わる分。
-- 判定順（fileencodings）と :Enc* コマンドは lua/config/options.lua、
-- 混在ツリーを検索するための小物は lua/config/encoding.lua。
return {
  -- ステータスラインに、UTF-8 以外で開いているファイルだけ印を出す。
  -- 「このファイルは何で開かれているか」が見えないと、化けた時に原因を切り分けられない。
  -- UTF-8（BOM なし・LF/CRLF）の時は何も出さない＝常時光らせない。
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function status()
        local parts = {}
        local fenc = vim.bo.fileencoding
        -- 空＝'encoding'（utf-8）を使う、の意味
        if fenc ~= "" and fenc ~= "utf-8" then
          parts[#parts + 1] = fenc
        end
        if vim.bo.bomb then
          parts[#parts + 1] = "BOM"
        end
        if vim.bo.fileformat == "mac" then
          parts[#parts + 1] = "CR"
        end
        return table.concat(parts, " ")
      end

      table.insert(opts.sections.lualine_x, 1, {
        status,
        cond = function()
          return vim.bo.buftype == "" and status() ~= ""
        end,
        color = function()
          return { fg = Snacks.util.color("DiagnosticWarn") }
        end,
      })
    end,
  },

  -- <leader>sJ … UTF-8 と Shift_JIS が混ざったツリーを 1 回で検索する grep（cwd 起点）。
  -- 既定の <leader>sg は日本語で検索すると UTF-8 のファイルにしか当たらない（rg は
  -- BOM なし CP932 を見分けられない）。sJ は検索語を「UTF-8 のバイト列 | CP932 のバイト列」
  -- の 2 択に展開し、結果の表示と列番号を UTF-8 に直す。仕組み＝lua/config/encoding.lua
  --
  -- sg と sJ を分けてあるのは、sJ では --no-unicode が効いて正規表現の意味が少し変わるため
  --（`.` が 1 バイト・`\w` と大文字小文字の無視が ASCII だけ）。
  -- 常にこちらを使いたくなったら、この keys の "<leader>sJ" を "<leader>sG" に変える
  --（sJ は cwd 起点＝sG と同じ範囲。root dir 起点にしたいなら cwd を LazyVim.root() に戻す）。
  {
    "folke/snacks.nvim",
    keys = {
      {
        "<leader>sJ",
        function()
          local Enc = require("config.encoding")
          Snacks.picker.grep({
            -- root dir ではなく cwd から検索する（LazyVim 既定の sg ではなく sG 側の挙動）。
            -- :pwd を動かせば検索範囲が動く＝サブディレクトリだけを狙える。
            cwd = vim.fn.getcwd(),
            title = "Grep (UTF-8 + Shift_JIS, cwd)",
            -- 文字コードの変換をさせず、バイト列として照合させる
            args = { "--no-unicode" },
            -- 打った検索語を 2 択に展開する（rg に渡る直前）
            filter = {
              transform = function(_, filter)
                filter.search = Enc.dual_pattern(filter.search)
              end,
            },
            -- CP932 のまま出てきた行を UTF-8 に直す
            transform = Enc.fix_item,
          })
        end,
        desc = "Grep (UTF-8 + Shift_JIS)",
      },
    },
  },
}
