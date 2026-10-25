-- 配色: kanagawa.nvim（wave）を土台にする。
--   * 地 … 塗らない。WezTerm の背景（黒・不透明度は wezterm/wezterm.lua）をそのまま見せる。
--     色を二重に持たないので、WezTerm 側を変えれば Neovim も揃う。フロート・ファイルツリーも同じ。
--   * UI … ガターも本文と同じ地にし、境界線は暗く沈める。
--   * コード … Visual Studio / VS Code（Dark+）の「役割ごとの色」を kanagawa のパレットの色で再現する。
--   * 見るべき所だけ強い色 … 枠（フロート・今いるペインのファイル名）＝ティール、
--     カーソル位置・今の検索結果・対応する括弧＝アンバー、エラー・警告＝波線。
--
-- コードの色（VS Code の役割 → kanagawa の色）
--   制御  if / for / return / throw / #include … 紫        oniViolet
--   宣言  local / function / const / int / nil … 青        crystalBlue
--   型・クラス・enum・名前空間                … ティール  waveAqua2
--   関数・メソッド                            … クリーム  carpYellow
--   変数・引数                                … 地の文字  fujiWhite（theme.ui.fg）
--   メンバ・プロパティ・テーブルのキー        … 淡い水色  lightBlue
--   文字列 … 桜色 sakuraPink ／ 数値 … 若草 springGreen ／ 定数・enum の値 … 橙 surimiOrange
--   マクロ … 薄紫 oniViolet2（Visual Studio のマクロの色）／ コメント … 灰 fujiGray（斜体なし）
return {
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000, -- 他のプラグインより先に色を決める
    opts = {
      -- 地は塗らないので、wave / dragon で変わるのはカーソル行・補完メニューなどの UI の色だけ
      theme = "wave",
      background = { dark = "wave", light = "lotus" },
      compile = false, -- true にすると、設定を変えるたびに :KanagawaCompile が要る
      undercurl = true, -- 診断・スペルの下線を波線にする
      -- 斜体・太字は使わない（VS / VS Code と同じく、役割は色だけで分ける）
      commentStyle = { italic = false },
      keywordStyle = { italic = false },
      statementStyle = { bold = false },
      transparent = true, -- 本文の地（Normal）を塗らない
      -- 今いないペインの地を暗くする dimInactive は使わない（そのペインだけ地を塗ることになり、WezTerm と揃わない）
      dimInactive = false,
      terminalColors = true,
      colors = {
        theme = {
          all = {
            ui = {
              -- ガター（行番号・サイン列）も塗らない＝本文と同じ地で、画面が縦に分断されない
              bg_gutter = "none",
              -- フロート（ポップアップ・検索・ファイルツリー）も塗らない。縁取り（FloatBorder）で区切る
              float = { bg = "none", bg_border = "none" },
            },
          },
        },
      },
      overrides = function(colors)
        local p = colors.palette
        local theme = colors.theme
        local ui = theme.ui
        local hl = {}

        -- groups を同じ文字色にする。kanagawa 側で太字・斜体が付いている物も消す
        local function paint(groups, color)
          for _, group in ipairs(groups) do
            hl[group] = { fg = color, bold = false, italic = false }
          end
        end

        ------------------------------------------------------------------
        -- コード本文
        ------------------------------------------------------------------
        -- treesitter の @keyword.xxx は、ここで決めていない物は @keyword の色になる。
        -- 大文字始まり（Keyword・Function …）は treesitter の無い filetype の syntax と、
        -- それにリンクしている補完メニュー・which-key などの色。

        -- 制御（流れが分かれる・飛ぶ所）＝紫。import / #include / #define も VS Code では紫
        paint({
          "@keyword.conditional",
          "@keyword.repeat",
          "@keyword.return",
          "@keyword.exception",
          "@keyword.coroutine", -- await / yield / co_await
          "@keyword.import",
          "@keyword.directive", -- #if / #pragma
          "@keyword.directive.define",
          "Conditional",
          "Repeat",
          "Exception",
          "PreProc",
          "Include",
          "Define",
          "PreCondit",
        }, p.oniViolet)

        -- 宣言・修飾・組み込みの型と値＝青
        paint({
          "@keyword", -- local / template など、ここで分けていない物
          "@keyword.function",
          "@keyword.operator", -- and / or / new / sizeof
          "@keyword.type", -- struct / class / enum
          "@keyword.modifier", -- const / static / public
          "@type.builtin", -- int / void / bool
          "@type.qualifier",
          "@boolean",
          "@constant.builtin", -- nil / nullptr
          "@variable.builtin", -- self / this
          "@lsp.mod.deduced", -- clangd は auto を推論した型（class 等）として送ってくる。キーワードの色に戻す
          "Keyword",
          "StorageClass",
          "Boolean",
        }, p.crystalBlue)

        -- ユーザー定義の型・クラス・enum・名前空間（@module → Type）＝ティール
        paint({
          "@type",
          "@type.definition",
          "@constructor",
          "@lsp.type.class",
          "@lsp.type.struct",
          "@lsp.type.enum",
          "@lsp.type.interface",
          "@lsp.type.typeParameter",
          "@lsp.type.type", -- clangd: typedef / using
          "@lsp.type.concept", -- C++20
          "Type",
        }, p.waveAqua2)
        -- Lua のテーブルの {} は treesitter では @constructor。型ではないので括弧と同じ色にする
        hl["@constructor.lua"] = { fg = theme.syn.punct }

        -- 関数・メソッド（定義も呼び出しも）＝クリーム色
        paint({
          "@function",
          "@function.call",
          "@function.method",
          "@function.method.call",
          "@function.builtin",
          "@lsp.type.function",
          "@lsp.type.method",
          "@lsp.typemod.function.readonly", -- kanagawa の既定だと青の太字になる
          "Function",
        }, p.carpYellow)
        -- 見出しは kanagawa だと Function にリンクしている。黄色にせず Title（青の太字）にする
        hl["@markup.heading"] = { link = "Title" }

        -- マクロ＝薄紫。#define などの指令（紫）とは分ける
        paint({ "@function.macro", "@constant.macro", "@lsp.type.macro", "Macro" }, p.oniViolet2)

        -- 変数・引数は地の文字色のまま（色を増やさない）
        paint({ "@variable", "@variable.parameter" }, ui.fg)
        -- @lsp.type.variable は塗らない（kanagawa の既定の fg = "none"＝下の treesitter の色が透ける）。
        -- 塗ると treesitter が付けた色（定数・組み込み）を消してしまう。普通の変数は上の @variable の色になる。
        -- グローバル・static・const な変数も同じく塗らない（kanagawa の既定は定数の橙）。
        -- clangd は const T& の引数や const char* にも readonly を付けるので、塗ると C++ が橙だらけになる
        hl["@lsp.typemod.variable.global"] = { fg = "none" }
        hl["@lsp.typemod.variable.static"] = { fg = "none" }
        hl["@lsp.mod.readonly"] = { fg = "none" }
        -- メンバ（obj.x の x・フィールド・テーブルのキー）＝淡い水色
        paint({ "@variable.member", "@property", "@lsp.type.property" }, p.lightBlue)

        -- 文字列を surimiOrange にしないのは、関数のクリーム色と色相が近く f("x") で紛れるため
        paint({ "@string", "String" }, p.sakuraPink)
        paint({ "@number", "Number" }, p.springGreen)
        -- 定数（treesitter が MAX_SIZE のような大文字の名前に付ける）・enum の値
        paint({ "@constant", "@lsp.type.enumMember", "Constant" }, p.surimiOrange)

        -- 演算子は句読点と同じ色。kanagawa の既定（黄土色）は関数のクリーム色と紛れる
        paint({ "@operator", "Operator" }, theme.syn.punct)

        paint({ "@comment", "Comment" }, p.fujiGray)

        ------------------------------------------------------------------
        -- UI
        ------------------------------------------------------------------
        local frame = p.waveAqua1 -- 枠＝今どこがアクティブか
        local spot = p.roninYellow -- 位置＝今どこを見ているか

        -- 境界線は暗く沈める。Neovim は境界線の色をペインごとには変えられない（1 本の線を両隣の
        -- ペインが共有する）ので、今いるペインは上端のファイル名とカーソルの十字で示す
        hl.WinSeparator = { fg = p.sumiInk4 }
        hl.FloatBorder = { fg = frame, bg = ui.float.bg_border }
        -- タブページの行の空き（bufferline の無い所）も塗らない。kanagawa の既定は本文の地の色
        hl.TabLineFill = { bg = "none" }
        -- 各ペイン上端のファイル名（lua/config/autocmds.lua の pane_winbar）。今いるペインだけ枠の色
        hl.PaneWinbar = { fg = ui.bg_m3, bg = frame, bold = true }
        hl.PaneWinbarNC = { fg = ui.fg_dim, bg = ui.bg_p1 }

        -- カーソルの十字（lua/config/autocmds.lua が今いるペインでだけ点ける。CursorColumn は
        -- CursorLine にリンク）。行番号の桁も同じ地にして、十字が番号のところで途切れないようにする
        hl.CursorLine = { bg = ui.bg_p2 }
        hl.CursorLineNr = { fg = spot, bg = ui.bg_p2, bold = true }

        -- 検索: 他の一致＝落ち着いた青、今の一致・入力中の一致＝アンバー
        hl.Search = { fg = ui.fg, bg = p.waveBlue2 }
        hl.CurSearch = { fg = ui.bg_m3, bg = spot, bold = true }
        hl.IncSearch = { fg = ui.bg_m3, bg = spot, bold = true }

        -- 対応する括弧と、カーソル下の名前の他の出現箇所（LSP）。書き込み箇所は下線も付ける
        hl.MatchParen = { fg = spot, bg = p.winterYellow, bold = true }
        hl.LspReferenceText = { bg = p.winterYellow }
        hl.LspReferenceRead = { bg = p.winterYellow }
        hl.LspReferenceWrite = { bg = p.winterYellow, underline = true, sp = spot }

        -- flash.nvim（s で飛ぶ）のラベルは、検索の青・アンバーのどちらとも違う赤で一番目立たせる。
        -- 一致箇所（FlashMatch / FlashCurrent）は既定のまま Search / IncSearch にリンク
        hl.FlashLabel = { fg = ui.bg_m3, bg = p.peachRed, bold = true }

        -- 診断: 彩度を落とさず、下線は波線
        hl.DiagnosticError = { fg = p.samuraiRed }
        hl.DiagnosticWarn = { fg = p.roninYellow }
        hl.DiagnosticUnderlineError = { undercurl = true, sp = p.samuraiRed }
        hl.DiagnosticUnderlineWarn = { undercurl = true, sp = p.roninYellow }

        return hl
      end,
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "kanagawa" } },
}
