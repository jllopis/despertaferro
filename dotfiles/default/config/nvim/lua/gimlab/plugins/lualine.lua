return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local lualine = require("lualine")
		local lazy_status = require("lazy.status")

		lualine.setup({
			options = {
				theme = "nord",
			},
			sections = {
				lualine_a = {
                    'mode',
---                    {
---                        'buffers',
---                        mode = 4
---                    },
                },
    			lualine_b = {'branch', 'diff', 'diagnostics'},
    			lualine_c = {'filename'},
                lualine_x = {
					{
                        function()
                          local ok, pomo = pcall(require, "pomo")
                          if not ok then
                            return ""
                          end

                          local timer = pomo.get_first_to_finish()
                          if timer == nil then
                            return ""
                          end

                          return "󰄉 " .. tostring(timer)
                        end,
				    },
					{
						lazy_status.updates,
						cond = lazy_status.has_updates,
						color = { fg = "#FF9E64" },
					},
					{ "encoding" },
					{ "fileformat" },
					{ "filetype" },
				},
    			lualine_y = {'progress'},
    			lualine_z = {'location'},
			},
		})
	end
}
