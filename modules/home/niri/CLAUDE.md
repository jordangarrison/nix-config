# Niri Configuration

This module provides a declarative niri configuration for the scrollable-tiling Wayland compositor.

## Overview

Niri is a scrollable-tiling compositor where workspaces scroll horizontally and windows within a workspace scroll vertically. This configuration is managed via `programs.niri.settings` from the [niri-flake](https://github.com/sodiboo/niri-flake).

## Key Differences from Hyprland

- **Build-time validation**: Niri config is validated at build time (no live reload errors)
- **KDL format**: Config is generated as KDL from Nix expressions
- **Scrollable tiling**: Windows tile in columns that scroll horizontally
- **No traditional workspaces**: Named workspaces exist but behave differently

## Shell Components

Currently using **noctalia-shell** for unified desktop shell:
- Status bar (replaces waybar)
- Notifications (replaces mako)
- Application launcher (replaces walker/rofi)
- Emoji picker (replaces rofimoji)
- Clipboard history (replaces rofi+cliphist script)
- Lock screen (replaces swaylock)
- Power menu (replaces wlogout)

**Note:** Rofi is only used for keybindings help display (`Mod+/`).

Wallpaper is managed separately via **swaybg**.

## Keybindings

### Program Launchers
| Keybinding | Action |
|------------|--------|
| `Mod+Return` | Ghostty terminal |
| `Mod+Shift+Return` | WezTerm SSH to endeavour |
| `Mod+B` | Brave browser |
| `Mod+E` | Emacs client |
| `Mod+N` | Obsidian |
| `Mod+F` | Yazi file manager (in Ghostty) |
| `Mod+Shift+F` | Nautilus file manager |
| `Mod+Shift+D` | Sweet Nothings voice dictation |
| `Mod+Space` | Noctalia launcher |
| `Mod+;` | Emoji picker (noctalia) |

### Window Controls
| Keybinding | Action |
|------------|--------|
| `Mod+Q` | Close window |
| `Mod+V` | Toggle floating |
| `Mod+M` | Maximize column |
| `Mod+Shift+M` | Fullscreen window |

### Focus Movement (vim-style)
| Keybinding | Action |
|------------|--------|
| `Mod+H/L` | Focus column left/right |
| `Mod+J/K` | Focus window down/up |
| `Mod+Arrow` | Same with arrow keys |

### Window Movement
| Keybinding | Action |
|------------|--------|
| `Mod+Shift+H/L` | Move column left/right |
| `Mod+Shift+J/K` | Move window down/up |
| `Mod+Shift+Arrow` | Same with arrow keys |

### Workspace Navigation
| Keybinding | Action |
|------------|--------|
| `Mod+1-0` | Switch to workspace 1-10 |
| `Mod+Shift+1-0` | Move window to workspace 1-10 |
| `Mod+Tab` | Focus previous workspace |
| `Mod+Ctrl+H/L` | Focus workspace left/right |
| `Mod+Ctrl+Shift+H/L` | Move window to workspace left/right |

### System
| Keybinding | Action |
|------------|--------|
| `Mod+Ctrl+Alt+L` | Lock screen (noctalia) |
| `Mod+C` | Clipboard history (noctalia) |
| `Mod+Shift+C` | Reload niri config |
| `Mod+Shift+Q` | Quit niri |
| `Mod+/` | Show keybindings help (rofi) |
| `Mod+Shift+/` | Show niri hotkey overlay (basic) |

### Screenshots
Screenshots are accessed via the which-key menu (`Mod+D → s`). Niri built-in screenshot binds remain:

| Keybinding | Action |
|------------|--------|
| `Print` | Screenshot (niri built-in) |
| `Shift+Print` | Screenshot window (niri built-in) |

### Which-Key Menu (Mod+D)

Interactive hierarchical command menu powered by `wlr-which-key`. Press `Mod+D` to open.

| Submenu | Key | Contents |
|---------|-----|----------|
| Power | p | Suspend, Reboot, Shutdown, Lock Screen |
| Screenshots | s | Region/Screen/Window capture with Annotate or Clipboard |
| Apps | a | AI Tools (Claude, ChatGPT, Gemini), System (btop, nmtui), Media (OBS) |
| Web | w | Mail, GitHub repos, Jira, Calendar, Meet |
| Media | m | Headphone/Speaker switching, Mic mute |
| Session | x | Reload config, Quit niri, Hotkey overlay |
| Display | d | Monitor focus/move |

**Configuration:** `modules/home/wlr-which-key/default.nix`

**Note:** Screenshots were moved from `Mod+Alt+S/A/C/F` keybinds into the which-key menu (`Mod+D → s`). The niri built-in `Print` and `Shift+Print` screenshot binds remain.

## Monitor Configuration

Configured for endeavour desktop with dual monitors:

- **DP-3** (Primary): 3840x2160 @ 60Hz, scale 1.5
- **DP-4** (Secondary): 2560x1440 @ 165Hz, 270 rotation (portrait)

All named workspaces (1-10) are assigned to DP-3. DP-4 gets dynamic workspaces only.

## Layout Settings

```
center-focused-column = "always"  # Focused column stays centered
default-column-width = { proportion = 0.5 }  # 50% width columns
gaps = 8  # Gap between windows
```

## Window Rules

- **Floating by default**: file dialogs, pop-ups, Nautilus, nm-applet, blueman
- **Workspace assignments**: Brave -> 1, Obsidian -> 4, Steam -> 10

## Adding New Keybindings

Edit `modules/home/niri/default.nix` in the `binds` section:

```nix
binds = {
  # Simple spawn
  "Mod+X".action.spawn = "program-name";

  # Spawn with arguments
  "Mod+Y".action.spawn = [ "program" "arg1" "arg2" ];

  # Niri actions (empty list for no-arg actions)
  "Mod+Z".action.close-window = [ ];

  # Noctalia IPC commands
  "Mod+Space".action.spawn = [ "noctalia-shell" "ipc" "call" "launcher" "toggle" ];
  "Mod+Semicolon".action.spawn = [ "noctalia-shell" "ipc" "call" "launcher" "emoji" ];
  "Mod+C".action.spawn = [ "noctalia-shell" "ipc" "call" "launcher" "clipboard" ];
};
```

**IMPORTANT:** When adding or modifying keybindings, you MUST also update the keybindings help script:
- **Script location:** `users/jordangarrison/configs/hypr/scripts/niri-keybinds-help.sh`
- **Why:** Niri doesn't expose keybindings via IPC (unlike Hyprland), so the help script maintains a static list
- **Trigger:** `Mod+/` shows the help via rofi

Keep both files in sync to ensure users can discover all available keybindings.

## Testing Changes

```bash
# Build without switching (validates config)
nh os build .

# Test configuration (switch temporarily)
nh os test .

# Apply permanently
nh os switch .
```

## Troubleshooting

### Config validation errors
Niri validates config at build time. Errors appear during `nh os build`. Common issues:
- Animation options need `.kind` suffix (e.g., `workspace-switch.kind = { spring = {...} }`)
- Transform expects integer rotation, not string
- Cursor options are `theme`/`size`, not `xcursor-theme`/`xcursor-size`

### Workspaces on wrong monitor
Explicitly set `open-on-output` for named workspaces:
```nix
workspaces = {
  "1" = { open-on-output = "DP-3"; };
};
```

### Noctalia not starting
Check if noctalia-shell is in spawn-at-startup and the package is installed from the flake input.

## Related Files

- `modules/nixos/niri-desktop.nix` - System-level niri configuration
- `flake.nix` - Niri and noctalia flake inputs
- `users/jordangarrison/configs/hypr/scripts/niri-keybinds-help.sh` - Keybindings help script (keep in sync!)
- `docs/adr/003-add-niri-scrolling-compositor.md` - Architecture decision record

## Resources

- [niri GitHub](https://github.com/YaLTeR/niri)
- [niri-flake](https://github.com/sodiboo/niri-flake)
- [noctalia-shell](https://github.com/noctalia-dev/noctalia-shell)
- [noctalia docs](https://docs.noctalia.dev/)
