---@type vim.lsp.Config
return {
    cmd = { "zls" },
    root_markers = { "zls.json", "build.zig", ".git" },
    filetypes = { "zig", "zir" },
    settings = {
      zls = {
        enable_autofix = false,
        enable_build_on_save = true,
        build_on_save_step = 'check', -- 'check', 'install', o 'test'
      }
    }
}
