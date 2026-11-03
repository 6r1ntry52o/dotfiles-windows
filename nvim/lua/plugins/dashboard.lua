-- 起動画面（snacks dashboard）に Obsidian Vault・Projects・Recent Files を出す。
-- LazyVim の既定は header / keys / startup だけ。sections を差し替えて間に 3 つ挟む。
--
-- Obsidian Vault は lua/config/vault.lua の registered()、Recent Files は v:oldfiles、
-- Projects はその各ファイルの git ルート（Obsidian Vault に出したものは除く）。
-- Obsidian Vault と Projects を選ぶと chdir して、そのディレクトリのセッション（persistence）が
-- あれば復元、無ければファイル picker を開く（snacks の既定動作）。
--
-- preset.keys（f/n/g/r/c/s/x/l/q）は LazyVim のものをそのまま使う。
local function vaults()
  return require("config.vault").registered()
end

local function not_vault(dir)
  local want = vim.fs.normalize(dir):lower()
  for _, path in ipairs(vaults()) do
    if path:lower() == want then
      return false
    end
  end
  return true
end

return {
  "folke/snacks.nvim",
  opts = {
    dashboard = {
      -- 自動キーは上の段から数字→英字の順。英字のうち preset と hjklq は snacks が飛ばす。
      autokeys = "1234567890abdeimoptuvwyz",
      sections = {
        { section = "header" },
        -- 件数は 5 ずつ: WezTerm を画面の左半分で起動するので縦に収まる量にする
        {
          icon = " ",
          title = "Obsidian Vault",
          section = "projects",
          dirs = vaults,
          limit = 5,
          indent = 2,
          padding = 1,
          enabled = function()
            return #vaults() > 0
          end,
        },
        {
          icon = " ",
          title = "Projects",
          section = "projects",
          filter = not_vault,
          limit = 5,
          indent = 2,
          padding = 1,
        },
        { icon = " ", title = "Recent Files", section = "recent_files", limit = 5, indent = 2, padding = 1 },
        { icon = " ", title = "Keymaps", section = "keys", indent = 2, padding = 1 },
        { section = "startup" },
      },
    },
  },
}
