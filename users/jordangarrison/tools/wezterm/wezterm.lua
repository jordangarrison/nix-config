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

-- Key bindings
local act = wezterm.action
config.keys = {
  -- Shift+Enter for Claude Code newline
  { key = 'Enter', mods = 'SHIFT', action = act.SendString '\x1b\r' },
}

if wezterm.target_triple:find('darwin') then
  -- macOS: CMD+D for right, CMD+SHIFT+D for below
  table.insert(config.keys, { key = 'd', mods = 'CMD', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } })
  table.insert(config.keys, { key = 'd', mods = 'CMD|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } })
  -- macOS: CMD+H/J/K/L for pane navigation (vim-style)
  table.insert(config.keys, { key = 'h', mods = 'CMD', action = act.ActivatePaneDirection 'Left' })
  table.insert(config.keys, { key = 'j', mods = 'CMD', action = act.ActivatePaneDirection 'Down' })
  table.insert(config.keys, { key = 'k', mods = 'CMD', action = act.ActivatePaneDirection 'Up' })
  table.insert(config.keys, { key = 'l', mods = 'CMD', action = act.ActivatePaneDirection 'Right' })
  -- macOS: CMD+[ / CMD+] for tab switching
  table.insert(config.keys, { key = '[', mods = 'CMD', action = act.ActivateTabRelative(-1) })
  table.insert(config.keys, { key = ']', mods = 'CMD', action = act.ActivateTabRelative(1) })
else
  -- Linux: CTRL+SHIFT+D for right, CTRL+SHIFT+E for below
  table.insert(config.keys, { key = 'd', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } })
  table.insert(config.keys, { key = 'e', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } })
  -- Linux: SUPER+H/J/K/L for pane navigation (vim-style)
  table.insert(config.keys, { key = 'h', mods = 'SUPER', action = act.ActivatePaneDirection 'Left' })
  table.insert(config.keys, { key = 'j', mods = 'SUPER', action = act.ActivatePaneDirection 'Down' })
  table.insert(config.keys, { key = 'k', mods = 'SUPER', action = act.ActivatePaneDirection 'Up' })
  table.insert(config.keys, { key = 'l', mods = 'SUPER', action = act.ActivatePaneDirection 'Right' })
  -- Linux: SUPER+[ / SUPER+] for tab switching
  table.insert(config.keys, { key = '[', mods = 'SUPER', action = act.ActivateTabRelative(-1) })
  table.insert(config.keys, { key = ']', mods = 'SUPER', action = act.ActivateTabRelative(1) })
end

-- initialize
return config
