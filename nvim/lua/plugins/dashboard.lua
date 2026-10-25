-- 起動画面（snacks dashboard）に Recent Files と Projects を出す。
-- LazyVim の既定は header / keys / startup だけ。sections を差し替えて間に 2 つ挟む。
--
-- Recent Files は v:oldfiles、Projects はその各ファイルの git ルート。
-- Projects を選ぶと chdir して、そのディレクトリのセッション（persistence）があれば復元、
-- 無ければファイル picker を開く（snacks の既定動作）。
--
-- preset.keys（f/n/g/r/c/s/x/l/q）は LazyVim のものをそのまま使う。
return {
  "folke/snacks.nvim",
  opts = {
    dashboard = {
      -- 自動キーを数字だけにする＝Recent が 1〜5、Projects が 6〜0。
      -- 既定（1234567890abc…）だと 10 件目以降が英字になり、preset の文字キーと混ざる。
      autokeys = "1234567890",
      sections = {
        { section = "header" },
        -- 件数は 5 ずつ: WezTerm を画面の左半分で起動するので縦に収まる量にする
        { icon = " ", title = "Recent Files", section = "recent_files", limit = 5, indent = 2, padding = 1 },
        { icon = " ", title = "Projects", section = "projects", limit = 5, indent = 2, padding = 1 },
        { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1 },
        { section = "startup" },
      },
    },
  },
}
