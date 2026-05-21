-- Autocommands and event handlers

-- Highlight yanked text
vim.api.nvim_create_autocmd("TextYankPost", {
  group = vim.api.nvim_create_augroup("YankHighlight", { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- Auto-format on save (will be extended by LSP plugins)
-- vim.api.nvim_create_autocmd("BufWritePre", {
--   group = vim.api.nvim_create_augroup("AutoFormat", { clear = true }),
--   callback = function()
--     -- LSP formatting will hook here
--   end,
-- })
