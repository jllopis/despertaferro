-- Utility functions and helpers

local M = {}

-- Create a keymap helper
function M.keymap(mode, lhs, rhs, opts)
  local default_opts = { noremap = true, silent = true }
  opts = vim.tbl_extend("force", default_opts, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

return M
