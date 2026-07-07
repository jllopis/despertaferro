return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
        dashboard = {
            enabled = true,
            preset = {
                header = [[
                         
   ▄████  ██▓ ███▄ ▄███▓ 
  ██▒ ▀█▒▓██▒▓██▒▀█▀ ██▒ 
 ▒██░▄▄▄░▒██▒▓██    ▓██░ 
 ░▓█  ██▓░██░▒██    ▒██  
 ░▒▓███▀▒░██░▒██▒   ░██▒ 
  ░▒   ▒ ░▓  ░ ▒░   ░  ░ 
   ░   ░  ▒ ░░  ░      ░ 
 ░ ░   ░  ▒ ░░      ░    
       ░  ░         ░    
                         ]],
                keys = {
                    { icon = " ", key = "e", desc = "New File", action = ":ene" },
                    { icon = " ", key = "-", desc = "Toggle file explorer", action = ":Oil --float" },
                    { icon = "󰱼 ", key = "f", desc = "Find File", action = ":Telescope find_files" },
                    { icon = " ", key = "w", desc = "Find Word", action = ":Telescope live_grep" },
                    { icon = "󰁯 ", key = "r", desc = "Restore Session For Current Directory", action = ":SessionRestore" },
                    { icon = "󰒲 ", key = "l", desc = "Open Lazy Plugin Manager", action = ":Lazy" },
                    { icon = " ", key = "q", desc = "Quit NVIM", action = ":qa" },
                },
            },
            sections = {
                { section = "header" },
                { section = "keys", gap = 1, padding = 1 },
                function()
                    if vim.fn.executable("fortune") ~= 1 then
                        return nil
                    end

                    local handle = io.popen("fortune")
                    if not handle then
                        return nil
                    end

                    local fortune = vim.trim(handle:read("*a") or "")
                    handle:close()

                    if fortune == "" then
                        return nil
                    end

                    return { footer = fortune, padding = 1 }
                end,
                { section = "startup" },
            },
        },
    },
}
