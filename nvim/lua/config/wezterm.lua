-- WezTerm へ nvim の状態を知らせる口。
local M = {}

---ユーザー変数を書く（OSC 1337 SetUserVar・値は base64）。WezTerm 側は pane:get_user_vars() で読む。
---@param name string
---@param value string
function M.set_user_var(name, value)
  local seq = ("\027]1337;SetUserVar=%s=%s\007"):format(name, vim.base64.encode(value))
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(seq) -- nvim 0.12+
  else
    io.stdout:write(seq)
  end
end

return M
