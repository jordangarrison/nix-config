# Hyprland Migration Plan for NixOS

## Overview

This document provides a step-by-step implementation plan for migrating from GNOME to Hyprland on NixOS. The configuration follows the same pattern as the existing Doom Emacs setup, using `mkOutOfStoreSymlink` to allow live editing without rebuilds.

## Context

- **User**: Jordan Garrison
- **Repository**: `~/dev/jordangarrison/nix-config`
- **Hosts**: endeavour (workstation), opportunity (Framework 12), voyager (MacBook Pro)
- **Current DE**: GNOME with 10 fixed workspaces, auto-move-windows, extensive keybindings
- **Target**: Hyprland running alongside GNOME (selectable at login)

## Architecture Decisions

| Component     | Choice                           | Rationale                                                           |
|---------------|----------------------------------|---------------------------------------------------------------------|
| Launcher      | Walker                           | Omarchy-style, Raycast-like features, home-manager module available |
| Screenshots   | grim + slurp + Satty             | Region select → annotation → save, all in nixpkgs                   |
| File Manager  | Yazi (terminal) + Nautilus (GUI) | Keyboard-driven primary, GUI fallback for drag-drop                 |
| Notifications | mako                             | Simple toasts, no notification center needed                        |
| Bar           | Waybar                           | Highly customizable, well-supported                                 |
| Lock          | hyprlock                         | Native Hyprland lock screen                                         |
| Idle          | hypridle                         | Native Hyprland idle daemon                                         |
| Wallpaper     | hyprpaper                        | Simple, native Hyprland wallpaper                                   |
| Clipboard     | cliphist + wl-clipboard          | Persistent clipboard history                                        |

---

## Phase 1: Create Directory Structure

### Task 1.1: Create config directories

Create the following directory structure in the nix-config repository:

```
users/jordangarrison/configs/hypr/
├── hyprland.conf
├── autostart.conf
├── keybinds.conf
├── rules.conf
├── theme.conf
├── hyprlock.conf
├── hypridle.conf
├── hyprpaper.conf
├── monitors/
│   ├── endeavour.conf
│   ├── opportunity.conf
│   └── voyager.conf
├── waybar/
│   ├── config.jsonc
│   └── style.css
├── mako/
│   └── config
└── satty/
    └── config.toml
```

**Commands:**
```bash
mkdir -p users/jordangarrison/configs/hypr/{monitors,waybar,mako,satty}
```

---

## Phase 2: Create Hyprland Configuration Files

### Task 2.1: Create `hyprland.conf` (main entry point)

**File**: `users/jordangarrison/configs/hypr/hyprland.conf`

**Requirements:**
- Source all modular config files (theme, keybinds, rules, autostart)
- Source host-specific monitor config from `~/.config/hypr/monitors.conf`
- Set environment variables for Wayland compatibility:
  - `XDG_CURRENT_DESKTOP=Hyprland`
  - `XDG_SESSION_TYPE=wayland`
  - `QT_QPA_PLATFORM=wayland`
  - `MOZ_ENABLE_WAYLAND=1`
  - `ELECTRON_OZONE_PLATFORM_HINT=auto`
- Configure input settings (keyboard layout, touchpad with natural scroll)
- Enable workspace gestures (3-finger swipe)
- Disable Hyprland logo/splash

**Template:**
```ini
# Source modular configs
source = ~/.config/hypr/theme.conf
source = ~/.config/hypr/autostart.conf
source = ~/.config/hypr/keybinds.conf
source = ~/.config/hypr/rules.conf
source = ~/.config/hypr/monitors.conf

# Environment variables
env = XDG_CURRENT_DESKTOP,Hyprland
env = XDG_SESSION_TYPE,wayland
env = QT_QPA_PLATFORM,wayland
env = MOZ_ENABLE_WAYLAND,1

# Input configuration
input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = true
        tap-to-click = true
    }
}

gestures {
    workspace_swipe = true
    workspace_swipe_fingers = 3
}

misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
```

### Task 2.2: Create `theme.conf`

**File**: `users/jordangarrison/configs/hypr/theme.conf`

**Requirements:**
- Rose Pine color scheme
- Gaps: 4px inner, 8px outer
- Border: 2px, active color `#c4a7e7`, inactive `#6e6a86`
- Rounding: 8px
- Blur enabled with subtle settings
- Smooth animations (not excessive)
- Dwindle layout as default

**Key settings:**
```ini
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 2
    col.active_border = rgba(c4a7e7ee) rgba(9ccfd8ee) 45deg
    col.inactive_border = rgba(6e6a86aa)
    layout = dwindle
}

decoration {
    rounding = 8
    blur {
        enabled = true
        size = 6
        passes = 3
    }
}

animations {
    enabled = true
    # Use easeOutQuint bezier for smooth feel
}

dwindle {
    preserve_split = true
    force_split = 2
}
```

### Task 2.3: Create `keybinds.conf`

**File**: `users/jordangarrison/configs/hypr/keybinds.conf`

**Requirements:**
- Main modifier: `SUPER` (physical Alt on Framework due to swapSuperAlt)
- Application launchers:
  - `SUPER+Return` → wezterm
  - `SUPER+B` → brave
  - `SUPER+E` → emacsclient -c
  - `SUPER+N` → obsidian
  - `SUPER+F` → nautilus
  - `SUPER+SHIFT+F` → wezterm -e yazi
- Launcher:
  - `SUPER+Space` → walker
  - `SUPER+Period` → walker --modules emojis
- Window management:
  - `SUPER+Q` → killactive
  - `SUPER+V` → togglefloating
  - `SUPER+M` → fullscreen 1 (maximize)
  - `SUPER+SHIFT+M` → fullscreen 0 (true fullscreen)
- Focus movement (vim-style):
  - `SUPER+H/J/K/L` → movefocus l/d/u/r
- Window movement:
  - `SUPER+SHIFT+H/J/K/L` → movewindow l/d/u/r
- Workspace switching:
  - `SUPER+1-0` → workspace 1-10
  - `SUPER+SHIFT+1-0` → movetoworkspace 1-10
- Multi-monitor:
  - `SUPER+comma/period` → focusmonitor l/r
  - `SUPER+SHIFT+comma/period` → movewindow mon:l/r
- Screenshots:
  - `Print` → region select with Satty annotation
  - `SHIFT+Print` → full screen with Satty
  - `SUPER+SHIFT+S` → quick region to clipboard (no annotation)
- Media keys:
  - Volume via wpctl
  - Brightness via brightnessctl
  - Media playback via playerctl
- System:
  - `SUPER+CTRL+ALT+L` → hyprlock
  - `SUPER+SHIFT+C` → hyprctl reload

**Screenshot command template:**
```bash
grim -g "$(slurp)" -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
```

### Task 2.4: Create `rules.conf`

**File**: `users/jordangarrison/configs/hypr/rules.conf`

**Requirements:**
- Workspace assignments matching GNOME auto-move-windows:
  - Workspace 1: brave-browser, firefox, chromium
  - Workspace 2: org.wezfurlong.wezterm, Alacritty, kitty
  - Workspace 3: Emacs, emacs
  - Workspace 4: ChatGPT, Claude (AI tools)
  - Workspace 5: todoist, Obsidian (tasks/notes)
  - Workspace 6: Code, Cursor, Zed
  - Workspace 7: discord, Slack, Signal, zoom
  - Workspace 8: virt-manager, Remmina
  - Workspace 9: Spotify, vlc, mpv
  - Workspace 10: 1Password, gnome-control-center, pavucontrol
- Floating rules:
  - File dialogs (Open File, Save File, etc.)
  - Calculator, pavucontrol, blueman-manager
  - 1Password (centered, 70% size)
  - Picture-in-Picture (pinned, top-right, 30% size)
- Opacity rules:
  - Full opacity for video players, games, fullscreen
- Layer rules:
  - Blur for walker, waybar, notifications

**Pattern for workspace rules:**
```ini
windowrulev2 = workspace 1, class:^(brave-browser)$
windowrulev2 = workspace 1, class:^(Brave-browser)$
```

### Task 2.5: Create `autostart.conf`

**File**: `users/jordangarrison/configs/hypr/autostart.conf`

**Requirements:**
- Core services:
  - `dbus-update-activation-environment` for XDG portal
  - `polkit-gnome-authentication-agent-1`
  - `gnome-keyring-daemon`
- Desktop services:
  - `hyprpaper` (wallpaper)
  - `waybar` (status bar)
  - `mako` (notifications)
  - `hypridle` (idle management)
  - `walker --gapplication-service` (launcher service)
- Clipboard:
  - `wl-paste --type text --watch cliphist store`
  - `wl-paste --type image --watch cliphist store`
- System tray:
  - `nm-applet --indicator`
  - `blueman-applet`
- User apps:
  - `1password --silent`
- Initialization:
  - `mkdir -p ~/Pictures/Screenshots`

### Task 2.6: Create monitor configs

**Files**: `users/jordangarrison/configs/hypr/monitors/`

#### `endeavour.conf` (workstation)
- Primary: DP-3, 3840x2160@60, position 0x0, scale 1.5
- Secondary: DP-4, 2560x1440@60, position 2560x0 (right of primary), transform 1 (90° rotation)
- Workspaces 1-7 on primary, 8-10 on secondary

#### `opportunity.conf` (Framework 12)
- Internal: eDP-1, 2256x1504@60, position 0x0, scale 1.5
- External fallback: HDMI-A-1/DP-1/DP-2, preferred, auto
- All workspaces on internal by default
- Extra touchpad settings (disable_while_typing)

#### `voyager.conf` (MacBook Pro)
- Internal: eDP-1, 2560x1600@60, position 0x0, scale 2
- External fallback: HDMI-A-1/DP-1, preferred, auto

---

## Phase 3: Create Supporting Configs

### Task 3.1: Create Waybar config

**File**: `users/jordangarrison/configs/hypr/waybar/config.jsonc`

**Requirements:**
- Position: top, height 32px, margin 4/8px (floating style)
- Modules left: hyprland/workspaces, hyprland/window
- Modules center: clock
- Modules right: tray, pulseaudio, network, battery, power button
- Workspace icons using Nerd Font symbols
- 10 persistent workspaces

**File**: `users/jordangarrison/configs/hypr/waybar/style.css`

**Requirements:**
- Rose Pine color scheme
- Font: FiraCode Nerd Font, 13px
- Transparent background with blur effect
- Rounded corners (12px)
- Subtle hover effects

### Task 3.2: Create mako config

**File**: `users/jordangarrison/configs/hypr/mako/config`

**Requirements:**
- Anchor: top-right
- Font: FiraCode Nerd Font 11
- Background: #191724ee (Rose Pine base with transparency)
- Border: 2px, #6e6a86, radius 8px
- Default timeout: 5000ms
- Max visible: 5
- Urgency-specific colors (critical = #eb6f92)
- On-click: dismiss

### Task 3.3: Create hyprlock config

**File**: `users/jordangarrison/configs/hypr/hyprlock.conf`

**Requirements:**
- Background: blurred screenshot
- Input field: centered, 300x50, rounded
- Labels: time (large), date, username
- Rose Pine colors

### Task 3.4: Create hypridle config

**File**: `users/jordangarrison/configs/hypr/hypridle.conf`

**Requirements:**
- 5 min: dim screen to 30%
- 10 min: lock screen
- 15 min: turn off display (dpms off)
- Before sleep: lock session
- After sleep: dpms on

### Task 3.5: Create Satty config

**File**: `users/jordangarrison/configs/hypr/satty/config.toml`

**Requirements:**
- Fullscreen mode enabled
- Early exit after save/copy
- Initial tool: arrow
- Copy command: wl-copy
- Annotation size factor: 2 (for HiDPI)
- Rose Pine colors for annotation palette

---

## Phase 4: Create Nix Module

### Task 4.1: Create home-manager module

**File**: `users/jordangarrison/configs/hypr/hyprland-home.nix`

**Requirements:**
- Package list:
  ```nix
  home.packages = with pkgs; [
    # Core
    hyprland hyprpaper hyprlock hypridle hyprpicker
    # Bar/notifications
    waybar mako
    # Launcher
    walker
    # Screenshots
    grim slurp satty wl-clipboard cliphist
    # File manager
    yazi
    # Utilities
    brightnessctl playerctl pamixer
    networkmanagerapplet blueman
    polkit_gnome wlogout
  ];
  ```

- Yazi configuration:
  ```nix
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
  };
  ```

- XDG config symlinks using `mkOutOfStoreSymlink`:
  - `hypr/*.conf` files
  - `waybar/*` files
  - `mako/config`
  - `satty/config.toml`

- GTK/Qt theming for consistency:
  - GTK theme: Adwaita-dark
  - Qt platform theme: adwaita
  - Cursor: Adwaita, size 24

### Task 4.2: Create monitor setup script

**File**: `users/jordangarrison/configs/hypr/setup-monitors.sh`

**Requirements:**
- Executable bash script
- Reads hostname
- Symlinks appropriate `monitors/*.conf` to `~/.config/hypr/monitors.conf`
- Falls back to creating a default config if host not found
- Prints helpful output

---

## Phase 5: Integration

### Task 5.1: Update home-linux.nix

**File**: `users/jordangarrison/home-linux.nix`

**Changes:**
Add import for the new Hyprland module:
```nix
imports = [
  ./home.nix
  ./configs/hypr/hyprland-home.nix
  # ... existing imports
];
```

### Task 5.2: Verify existing Hyprland NixOS module

**File**: `modules/hyprland-desktop.nix` (or similar)

**Requirements:**
- Ensure `programs.hyprland.enable = true` is set
- XDG portal configuration for Hyprland
- Session should appear in display manager

---

## Phase 6: Testing & Validation

### Task 6.1: Build and switch

```bash
cd ~/dev/jordangarrison/nix-config
nh os switch .#endeavour  # or appropriate hostname
```

### Task 6.2: First boot checklist

1. [ ] Log out of GNOME
2. [ ] Select Hyprland from session menu
3. [ ] Log in
4. [ ] Run `~/.config/hypr/setup-monitors.sh`
5. [ ] Press `SUPER+SHIFT+C` to reload config

### Task 6.3: Functionality tests

- [ ] `SUPER+Return` opens WezTerm
- [ ] `SUPER+Space` opens Walker launcher
- [ ] `SUPER+1-0` switches workspaces
- [ ] `Print` captures region and opens Satty
- [ ] Notifications appear as toasts
- [ ] Waybar displays correctly
- [ ] Volume/brightness keys work
- [ ] Lock screen works (`SUPER+CTRL+ALT+L`)
- [ ] Multi-monitor layout correct (endeavour only)

---

## File Reference

All files to be created:

| Path                                                          | Description             |
|---------------------------------------------------------------|-------------------------|
| `users/jordangarrison/configs/hypr/hyprland.conf`             | Main config entry point |
| `users/jordangarrison/configs/hypr/theme.conf`                | Visual appearance       |
| `users/jordangarrison/configs/hypr/keybinds.conf`             | Keyboard shortcuts      |
| `users/jordangarrison/configs/hypr/rules.conf`                | Window rules            |
| `users/jordangarrison/configs/hypr/autostart.conf`            | Startup services        |
| `users/jordangarrison/configs/hypr/hyprlock.conf`             | Lock screen             |
| `users/jordangarrison/configs/hypr/hypridle.conf`             | Idle management         |
| `users/jordangarrison/configs/hypr/hyprpaper.conf`            | Wallpaper               |
| `users/jordangarrison/configs/hypr/monitors/endeavour.conf`   | Workstation monitors    |
| `users/jordangarrison/configs/hypr/monitors/opportunity.conf` | Framework 12 monitors   |
| `users/jordangarrison/configs/hypr/monitors/voyager.conf`     | MacBook monitors        |
| `users/jordangarrison/configs/hypr/waybar/config.jsonc`       | Status bar config       |
| `users/jordangarrison/configs/hypr/waybar/style.css`          | Status bar styling      |
| `users/jordangarrison/configs/hypr/mako/config`               | Notification daemon     |
| `users/jordangarrison/configs/hypr/satty/config.toml`         | Screenshot tool         |
| `users/jordangarrison/configs/hypr/setup-monitors.sh`         | Monitor setup script    |
| `users/jordangarrison/configs/hypr/hyprland-home.nix`         | Home-manager module     |

---

## Notes for Agent

1. **Do not modify** existing GNOME configuration - Hyprland runs alongside it
2. **Use mkOutOfStoreSymlink** for all config files to allow live editing
3. **Rose Pine colors**: base=#191724, text=#e0def4, accent=#c4a7e7, love=#eb6f92
4. **Test incrementally** - each phase should result in a working (if incomplete) setup
5. **Preserve existing hyprland-desktop.nix** module if it exists - only add home-manager config
6. The user has `swapSuperAlt = true` on Framework, so SUPER = physical Alt key

## Reference Configs

Example configs have been generated and are available in the `hyprland-config/` directory for reference. Use these as templates but adapt paths and settings as needed.
