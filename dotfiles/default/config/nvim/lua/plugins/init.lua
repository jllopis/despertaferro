-- Automatic plugin download
vim.pack.add({
  "https://github.com/shaunsingh/nord.nvim",
})

-- Plugin configurations loader
-- Each plugin configuration is in its own file

require("plugins.colorscheme")
-- require("plugins.telescope")
-- require("plugins.treesitter")
-- require("plugins.lsp")
-- require("plugins.completion")
-- require("plugins.statusline")
-- require("plugins.editor")
