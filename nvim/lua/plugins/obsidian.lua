-- Obsidian vault を nvim 側から触る口。vault の場所は PC ごとに違うので、リポには書かず
-- `~/.dotfiles.json` の "vault" から読む（lua/config/machine.lua・README の「PC ごとの設定」）。
-- 入れた動機は「今開いているノートを Obsidian アプリで開く」＝ `:Obsidian open`。
-- 本家 epwalsh/obsidian.nvim は更新が止まり、コミュニティ fork が後継（要 nvim 0.11+・手元は 0.11.6）。
--
-- この vault は AI の記録（engram・mulmoclaude）と麟太郎の執筆（exocortex）が同居しているので、
-- 「nvim 側が md の中身を勝手に変える」既定は切ってある（frontmatter・ui）。
-- vault 内の md バッファでは、このプラグインが <CR>（カーソル下のリンク追従／チェックボックス切替）と
-- [o / ]o（前後のリンクへ移動）をバッファローカルに足す＝vault の外の md は何も変わらない。
local vault = require("config.machine").str("vault")

return {
  "obsidian-nvim/obsidian.nvim",
  -- vault を設定していない PC では読み込まない（`~/.dotfiles.json` の "vault" が空）
  enabled = vault ~= nil,
  version = "*", -- リリースタグに追従（main は未リリースの機能を含む）
  ft = { "markdown" }, -- md を開いた時に初めて起きる
  ---@module 'obsidian'
  ---@type obsidian.config
  opts = {
    legacy_commands = false, -- 旧 :ObsidianOpen 形式のコマンドを作らない（4.0.0 で削除予定）

    -- path の最後の名前が、そのまま Obsidian 側の vault 名として URI に乗る
    -- （commands/open.lua が vim.fs.basename(path) を使う）。`~/.dotfiles.json` の "vault" の
    -- フォルダ名が、Obsidian が開いている vault 名と一致している必要がある。
    workspaces = {
      { name = vim.fs.basename(vault or ""), path = vault or "" },
    },

    -- 🔴 保存時に frontmatter を作らせない。
    -- 既定 true では vault 内の md を :w するたび BufWritePre で id/aliases/tags が注入される
    -- （autocmds.lua → Note:update_frontmatter）。exocortex の散文や engram が書き換わるので切る。
    frontmatter = { enabled = false },

    -- `:Obsidian open` が叩く obsidian:// URI の開き方。
    -- 既定の vim.ui.open は Windows で `cmd.exe /c start "" <uri>` に展開され、クエリの & を
    -- cmd がコマンド区切りとして食う＝ file= が落ちて vault しか開かない（2026-10-05 実測）。
    -- rundll32 のプロトコルハンドラは cmd を通らないので URI がそのまま届く
    -- （explorer.exe・pwsh Start-Process は届かなかった）。
    -- https などの外部リンクはこの func を通らず vim.ui.open 直呼びなので、ここは obsidian:// 専用。
    open = {
      func = function(uri)
        vim.system({ "rundll32.exe", "url.dll,FileProtocolHandler", uri }, { detach = true })
      end,
    },

    picker = { name = "snacks.picker" }, -- LazyVim 既定のピッカーに寄せる

    -- 日次ノートの正本は exocortex/daily/YYYY-MM-DD.md。
    -- 既定の default_tags = { "daily-notes" } は既存の daily に無いタグなので入れない。
    -- `:Obsidian today` は素の daily を作る（Obsidian 側のテンプレは使わない）。
    daily_notes = {
      folder = "exocortex/daily",
      date_format = "YYYY-MM-DD",
      default_tags = {},
    },

    -- 新規ノートは exocortex 配下（Obsidian 側の newFileFolderPath と同じ）
    notes_subdir = "exocortex",
    new_notes_location = "notes_subdir",
    templates = { folder = "exocortex/templates" },

    -- 画像の貼り付け先。既定は vault 直下に attachments/ を新造するので assets に寄せる。
    attachments = { folder = "exocortex/assets" },

    -- 装飾と常駐表示は出さない（conceal で本文を隠す・テーマ外の固定色・フッターの常時表示）。
    ui = { enable = false },
    footer = { enabled = false },

    -- private な器は検索・補完に出さない（Obsidian 側 .obsidian/app.json の userIgnoreFilters と同じ）。
    -- 末尾 "/" ではなく "/**" で書く（プラグインの glob はこの形で深い階層まで効く）。
    file = {
      ignore_filters = {
        "mulmoclaude/conversations/searches/**",
        "mulmoclaude/conversations/chat/**",
        "mulmoclaude/data/health/**",
        "mulmoclaude/data/health-checkup/**",
        "mulmoclaude/data/browser-history/**",
        "mulmoclaude/data/cafeteria-menu/**",
        "mulmoclaude/data/_archive/**",
        "mulmoclaude/_archive/**",
        "engram/archive/**",
        "engram/inbox/**",
      },
    },
  },
}
