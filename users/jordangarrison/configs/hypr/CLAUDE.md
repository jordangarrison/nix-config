# Hyprland Configuration

This directory contains the Hyprland window manager configuration for Jordan's NixOS systems.

## Architecture

Configs are **symlinked via Home Manager** using `mkOutOfStoreSymlink`, allowing **live editing** without rebuilding. Changes take effect immediately after `hyprctl reload` or restart.

The Home Manager module at `modules/home/hyprland/default.nix` handles:
- Package installation (hyprpaper, hyprlock, waybar, etc.)
- Symlinking configs to `~/.config/hypr/`
- GTK/Qt theming

## Directory Structure

```
hypr/
├── hyprland.conf       # Main entry point - sources all other configs
├── theme.conf          # Visual theming (gaps, borders, animations)
├── keybinds.conf       # All keyboard shortcuts
├── rules.conf          # Window rules and workspace assignments
├── autostart.conf      # Programs launched at startup
├── hyprpaper.conf      # Wallpaper daemon configuration
├── hyprlock.conf       # Lock screen configuration
├── hypridle.conf       # Idle/sleep behavior
├── monitors/           # Host-specific monitor configs
│   ├── endeavour.conf  # Desktop: DP-3 (4K), DP-4 (1440p portrait)
│   ├── opportunity.conf # Framework laptop: eDP-1
│   └── voyager.conf    # MacBook: eDP-1
├── scripts/            # Helper scripts
│   ├── set-wallpaper.sh      # Set wallpaper on all monitors
│   ├── clipboard.sh          # Clipboard history picker
│   ├── window-switcher.sh    # MRU window switcher
│   ├── keybinds-help.sh      # Show keybind help
│   └── screenshot-*.sh       # Various screenshot modes
├── waybar/             # Status bar
├── mako/               # Notifications
├── walker/             # Application launcher
├── rofi/               # Alternative launcher
└── satty/              # Screenshot annotation tool
```

## Monitor Configuration

Each host has its own monitor config in `monitors/`. The active config is symlinked to `~/.config/hypr/monitors.conf` based on hostname.

### Adding a New Host

1. Create `monitors/<hostname>.conf`
2. Define monitor layout:
   ```conf
   # Format: monitor = name, resolution@refresh, position, scale, transform
   monitor = eDP-1, 2256x1504@60, 0x0, 1.5

   # Workspace assignments
   workspace = 1, monitor:eDP-1, default:true
   ```
3. Update Home Manager or manually symlink

### Finding Monitor Names

```bash
hyprctl monitors
```

## Wallpaper Management

Wallpapers are stored in `users/jordangarrison/wallpapers/`.

### Set Wallpaper (Runtime)

```bash
# Set same wallpaper on all monitors
./scripts/set-wallpaper.sh /path/to/wallpaper.jpg

# Set on specific monitor
hyprctl hyprpaper wallpaper "DP-3,/path/to/wallpaper.jpg"
```

### Set Default Wallpaper (Persistent)

1. Add wallpaper to `users/jordangarrison/wallpapers/`
2. Edit `hyprpaper.conf`:
   ```conf
   preload = /path/to/wallpaper.jpg
   wallpaper = DP-3,/path/to/wallpaper.jpg
   wallpaper = DP-4,/path/to/wallpaper.jpg
   ```
3. Edit `autostart.conf` (for workaround):
   ```conf
   exec-once = sleep 1 && hyprctl hyprpaper wallpaper "DP-3,/path/to/wallpaper.jpg"
   ```
4. Reload: `hyprctl reload`

**Note:** Due to symlink timing issues, wallpapers are also set via `hyprctl` in autostart as a workaround.

## Key Bindings

Main modifier: `SUPER` (Meta/Windows key)

### Essential Bindings

| Binding | Action |
|---------|--------|
| `Super+Return` | Terminal (WezTerm) |
| `Super+Space` | App launcher (Walker) |
| `Super+;` | Emoji picker (rofimoji) |
| `Super+B` | Browser (Brave) |
| `Super+E` | Editor (Emacs) |
| `Super+N` | Notes (Obsidian) |
| `Super+Q` | Close window |
| `Super+V` | Toggle floating |
| `Super+M` | Maximize |
| `Super+/` | Show keybind help |

### Navigation

| Binding | Action |
|---------|--------|
| `Super+H/J/K/L` | Focus left/down/up/right |
| `Super+Shift+H/J/K/L` | Move window |
| `Super+1-0` | Switch to workspace 1-10 |
| `Super+Shift+1-0` | Move window to workspace |
| `Super+,` / `Super+.` | Focus left/right monitor |
| `Super+Tab` | Window switcher |

### Screenshots

| Binding | Action |
|---------|--------|
| `Super+Alt+S` | Region select + Satty annotation |
| `Super+Alt+A` | Full screen + Satty annotation |
| `Super+Alt+C` | Region to clipboard |
| `Super+Alt+F` | Full screen to clipboard |

### System

| Binding | Action |
|---------|--------|
| `Super+C` | Clipboard history |
| `Super+Shift+C` | Reload config |
| `Super+Ctrl+Alt+L` | Lock screen |
| `Super+Shift+Q` | Exit Hyprland |

## Common Tasks

### Reload Configuration

```bash
hyprctl reload
```

### Check Logs

```bash
# Hyprland log
cat /tmp/hypr/$(ls -t /tmp/hypr/ | head -1)/hyprland.log

# Or via hyprctl
hyprctl log
```

### Debug Window Issues

```bash
# List all windows
hyprctl clients

# Get active window info
hyprctl activewindow
```

### Troubleshooting

**Wallpaper not showing:**
```bash
# Check if hyprpaper is running
pgrep hyprpaper

# Restart hyprpaper
pkill hyprpaper && hyprpaper &

# Manually set wallpaper
hyprctl hyprpaper wallpaper "DP-3,/path/to/wallpaper.jpg"
```

**Monitor not detected:**
```bash
# List available monitors
hyprctl monitors

# Check kernel logs
dmesg | grep -i drm
```

## Component Tools

| Tool | Purpose | Config |
|------|---------|--------|
| **hyprpaper** | Wallpaper daemon | `hyprpaper.conf` |
| **hyprlock** | Lock screen | `hyprlock.conf` |
| **hypridle** | Idle management | `hypridle.conf` |
| **waybar** | Status bar | `waybar/` |
| **mako** | Notifications | `mako/config` |
| **walker** | App launcher | `walker/config.toml` |
| **cliphist** | Clipboard history | (runtime only) |
| **satty** | Screenshot annotation | `satty/config.toml` |

## References

- [Hyprland Wiki](https://wiki.hyprland.org/)
- [Hyprland Config Reference](https://wiki.hyprland.org/Configuring/)
- [hyprpaper](https://github.com/hyprwm/hyprpaper)
- [hyprlock](https://github.com/hyprwm/hyprlock)
