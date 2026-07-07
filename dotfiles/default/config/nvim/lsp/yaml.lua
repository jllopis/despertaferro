---@type vim.lsp.Config
return {
    filetypes = { "yaml" },
    cmd = { "yaml-language-server", "--stdio" },
    settings = {
        yaml = {
            -- Using the schemastore plugin for schemas.
            schemastore = { enable = false, url = "" },
            schemas = require("schemastore").yaml.schemas(),
        },
    },
}
