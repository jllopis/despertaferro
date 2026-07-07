---@type vim.lsp.Config
return {
    cmd = { "kulala-ls", "--stdio" },
    filetypes = { "http", "rest" },
    root_markers = {
        "http-client.env.json",
        "http-client.private.env.json",
        ".env",
        ".git",
    },
}
