---@type vim.lsp.Config
return {
    cmd = { "docker-compose-langserver", "--stdio" },
    root_markers = { "docker_compose*.yml", "docker-compose.yml" },
    filetypes = { "yaml.docker-compose" },
    single_file_support = true,
}
