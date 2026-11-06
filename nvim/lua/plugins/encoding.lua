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

  -- 既定の grep（<leader>/・sg・sG・sw・sW・sB）で、UTF-8 と Shift_JIS が混ざったツリーを 1 回で検索する。
  -- 素の snacks は rg の出力をそのまま出す＝BOM なし CP932 のファイルは日本語で当たらず、ASCII で当たった行と
  -- 右のプレビューは化ける（rg は BOM なし CP932 を見分けられない）。検索語を「UTF-8 | CP932 のバイト列」の
  -- 2 択に展開し、結果の表示・列番号・右のプレビューを UTF-8 に直す。仕組み＝lua/config/encoding.lua
  --
  -- 2026-11-06 までは <leader>sJ に分けていた（--no-unicode で正規表現の意味が少し変わったため）。
  -- CP932 の側だけをバイト列で照合するようにしたので、既定の grep に入れた。
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      local grep = require("config.encoding").grep
      opts.picker = opts.picker or {}
      opts.picker.sources = opts.picker.sources or {}
      for _, name in ipairs({ "grep", "grep_word", "grep_buffers" }) do
        opts.picker.sources[name] = vim.tbl_deep_extend("force", opts.picker.sources[name] or {}, grep)
      end
    end,
  },
}
