-- gitsigns（LazyVim 同梱）に足す分。
-- 259 文字以上のフォルダにあるファイルを開くと、gitsigns が git を起動できずに Lua のエラーを出していた。
-- そういうファイルだけ、リポの場所を先に渡す＝lua/config/longpath.lua の gitsigns_attach_pre。
return {
  "lewis6991/gitsigns.nvim",
  opts = {
    _on_attach_pre = function(bufnr, callback)
      require("config.longpath").gitsigns_attach_pre(bufnr, callback)
    end,
  },
}
