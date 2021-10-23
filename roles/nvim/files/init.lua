require('plugins')
require('basic')
require('autocommands')
require('lightline')
require('maps')

-- Configure plugins
local config = vim.fn['stdpath']('config')..'/lua/'
dofile(config..'pluginsConfig/nvim-tree.lua')
dofile(config..'pluginsConfig/telescope.lua')
dofile(config..'pluginsConfig/bufferline.lua')

