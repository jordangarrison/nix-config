-- pull the wezterm api
local wezterm = require 'wezterm'

-- Create config
local config = wezterm.config_builder()

-- start customizations
-- Theme
config.color_scheme = 'rose-pine'
config.font = wezterm.font('Source Code Pro', { bold = true })
config.font_size = 14
config.default_cursor_style = 'SteadyBar'

-- background
config.window_background_opacity = 0.95

-- Custom selection colors
config.colors = {
  selection_fg = '#26233a',    -- Dark foreground (can adjust based on your theme)
  selection_bg = '#ebbcba',    -- Light pinkish highlight (adjust to your preference)
}

-- ssh domains
config.ssh_domains = {
  {
    name = 'endeavour',
    remote_address = 'endeavour',
    username = 'jordangarrison'
  }
}

-- initialize
return config
