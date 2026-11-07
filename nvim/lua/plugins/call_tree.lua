-- 呼び出しの階層をツリーで（gaI＝呼び出し元・gaO＝呼び出し先）。本体は config/call_tree.lua。
-- 1 段だけの一覧は LazyVim の gai / gao（snacks）のまま。
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          -- stylua: ignore
          keys = {
            { "gaI", function() require("config.call_tree").open("incoming") end, desc = "Calls Incoming (tree)", has = "callHierarchy/incomingCalls" },
            { "gaO", function() require("config.call_tree").open("outgoing") end, desc = "Calls Outgoing (tree)", has = "callHierarchy/outgoingCalls" },
          },
        },
      },
    },
  },
}
