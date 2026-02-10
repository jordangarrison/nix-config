# wlr-which-key Menu Design

## Overview

Add `wlr-which-key` as an interactive, hierarchical command menu for the Niri compositor. Triggered by `Mod+D`, it provides both actionable commands (power, screenshots, app launching) and discovery reference (display controls, session management).

## Package

- **Package:** `wlr-which-key` (v1.3.0, already in nixpkgs unstable)
- **No new flake input required**
- **Compositor:** Niri only

## Trigger

- **Keybinding:** `Mod+D`
- **Replaces:** `Mod+/` keybinds-help.sh (rofi-based static list) can be kept or removed
- **Replaces:** `Mod+Alt+S/A/C/F` screenshot keybinds (removed in favor of menu)

## Implementation Approach

Generate YAML config declaratively using `pkgs.writeText` and wrap with `pkgs.writeShellScriptBin`. Create a Home Manager module at `modules/home/wlr-which-key/default.nix`.

## Menu Structure

```
ROOT MENU (Mod+D)
├── [p] Power
│   ├── [s] Suspend
│   ├── [r] Reboot
│   ├── [o] Shutdown
│   └── [l] Lock Screen
│
├── [s] Screenshots
│   ├── [r] Region -> Annotate
│   ├── [s] Screen -> Annotate
│   ├── [w] Window -> Annotate
│   ├── [c] Region -> Clipboard
│   ├── [f] Screen -> Clipboard
│   ├── [a] All Monitors -> Annotate
│   └── [A] All Monitors -> Clipboard
│
├── [a] Apps
│   ├── [a] AI Tools
│   │   ├── [c] Claude (PWA)
│   │   ├── [g] ChatGPT (PWA)
│   │   └── [m] Gemini (PWA)
│   ├── [s] System
│   │   ├── [b] btop
│   │   └── [n] Network (nmtui)
│   └── [m] Media
│       └── [o] OBS Studio
│
├── [w] Web
│   ├── [m] Mail
│   │   ├── [p] Personal Gmail (tab)
│   │   ├── [w] Work Gmail (tab)
│   │   ├── [f] Family Gmail (tab)
│   │   └── [i] iCloud Mail (tab)
│   ├── [g] GitHub
│   │   ├── [p] Personal
│   │   │   ├── [p] Profile
│   │   │   └── [n] Nix Config
│   │   ├── [f] Flocasts
│   │   │   ├── [o] Org
│   │   │   ├── [i] Infra Base Services
│   │   │   ├── [w] Web Monorepo
│   │   │   └── [t] Teams
│   │   └── [e] Enterprise
│   │       ├── [d] Dashboard
│   │       ├── [p] People
│   │       └── [a] AI Controls
│   ├── [j] Jira Board (tab)
│   ├── [c] Calendar (tab)
│   └── [t] Meet (PWA)
│
├── [m] Media
│   ├── [h] Switch to Headphones
│   ├── [s] Switch to Speakers
│   └── [m] Toggle Mic Mute
│
├── [x] Session
│   ├── [r] Reload Niri Config
│   ├── [q] Quit Niri
│   └── [h] Hotkey Overlay
│
└── [d] Display
    ├── [h] Focus Monitor Left
    ├── [l] Focus Monitor Right
    ├── [H] Move Window to Monitor Left
    ├── [L] Move Window to Monitor Right
    └── [s] Scale (host-specific, TBD)
```

## Commands

### Power

| Key | Description | Command |
|-----|-------------|---------|
| s | Suspend | `systemctl suspend` |
| r | Reboot | `systemctl reboot` |
| o | Shutdown | `systemctl poweroff` |
| l | Lock Screen | `noctalia-shell ipc call lockScreen lock` |

### Screenshots

| Key | Description | Command |
|-----|-------------|---------|
| r | Region -> Annotate | `screenshot-region-satty.sh` |
| s | Screen -> Annotate | `screenshot-focused-monitor-satty.sh` (new) |
| w | Window -> Annotate | `screenshot-window-satty.sh` (new) |
| c | Region -> Clipboard | `screenshot-region-clipboard.sh` |
| f | Screen -> Clipboard | `screenshot-focused-monitor-clipboard.sh` (new) |
| a | All Monitors -> Annotate | `screenshot-full-satty.sh` |
| A | All Monitors -> Clipboard | `screenshot-full-clipboard.sh` |

### Apps - AI Tools

| Key | Description | Command |
|-----|-------------|---------|
| c | Claude | `brave --app=https://claude.ai` |
| g | ChatGPT | `brave --app=https://chat.openai.com` |
| m | Gemini | `brave --app=https://gemini.google.com` |

### Apps - System

| Key | Description | Command |
|-----|-------------|---------|
| b | btop | `alacritty -e btop` |
| n | Network | `alacritty -e nmtui` |

### Apps - Media

| Key | Description | Command |
|-----|-------------|---------|
| o | OBS Studio | `obs` |

### Web - Mail

| Key | Description | Command |
|-----|-------------|---------|
| p | Personal Gmail | `brave https://mail.google.com/mail/u/0/#inbox` |
| w | Work Gmail | `brave https://mail.google.com/mail/u/1/#inbox` |
| f | Family Gmail | `brave https://mail.google.com/mail/u/2/#inbox` |
| i | iCloud Mail | `brave https://icloud.com/mail` |

### Web - GitHub - Personal

| Key | Description | Command |
|-----|-------------|---------|
| p | Profile | `brave https://github.com/jordangarrison` |
| n | Nix Config | `brave https://github.com/jordangarrison/nix-config` |

### Web - GitHub - Flocasts

| Key | Description | Command |
|-----|-------------|---------|
| o | Org | `brave https://github.com/flocasts` |
| i | Infra Base Services | `brave https://github.com/flocasts/infra-base-services` |
| w | Web Monorepo | `brave https://github.com/flocasts/web-monorepo` |
| t | Teams | `brave https://github.com/orgs/flocasts/teams` |

### Web - GitHub - Enterprise

| Key | Description | Command |
|-----|-------------|---------|
| d | Dashboard | `brave https://github.com/enterprises/flosports/` |
| p | People | `brave https://github.com/enterprises/flosports/people` |
| a | AI Controls | `brave https://github.com/enterprises/flosports/ai-controls/agents` |

### Web - Flat Entries

| Key | Description | Command |
|-----|-------------|---------|
| j | Jira Board | `brave https://flocasts.atlassian.net/jira/software/c/projects/INFRA/boards/166` |
| c | Calendar | `brave https://calendar.google.com/calendar/u/1/r/week` |
| t | Meet | `brave --app=https://meet.google.com` |

### Media

| Key | Description | Command |
|-----|-------------|---------|
| h | Headphones | TBD (wpctl sink switching script) |
| s | Speakers | TBD (wpctl sink switching script) |
| m | Toggle Mic Mute | `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` |

### Session

| Key | Description | Command |
|-----|-------------|---------|
| r | Reload Config | `niri msg action reload-config` |
| q | Quit Niri | `niri msg action quit` |
| h | Hotkey Overlay | `niri msg action show-hotkey-overlay` |

### Display

| Key | Description | Command |
|-----|-------------|---------|
| h | Focus Monitor Left | `niri msg action focus-monitor-left` |
| l | Focus Monitor Right | `niri msg action focus-monitor-right` |
| H | Move to Monitor Left | `niri msg action move-window-to-monitor-left` |
| L | Move to Monitor Right | `niri msg action move-window-to-monitor-right` |
| s | Scale | Host-specific submenu (TBD) |

## New Files Needed

### Module

- `modules/home/wlr-which-key/default.nix` — Home Manager module generating YAML config and wrapper script

### New Screenshot Scripts

- `screenshot-focused-monitor-satty.sh` — Capture focused monitor, open in Satty
- `screenshot-window-satty.sh` — Capture active window, open in Satty
- `screenshot-focused-monitor-clipboard.sh` — Capture focused monitor to clipboard

### Audio Switching Script

- Script to switch default audio sink between headphones and speakers via `wpctl`

## Keybind Changes

### Add

- `Mod+D` — Open wlr-which-key root menu

### Remove (moved to which-key Screenshots submenu)

- `Mod+Alt+S` — Region + Satty
- `Mod+Alt+A` — Full screen + Satty
- `Mod+Alt+C` — Region to clipboard
- `Mod+Alt+F` — Full screen to clipboard

### Keep (unchanged)

- `Print` — niri built-in screenshot
- `Shift+Print` — niri built-in window screenshot
- All other existing keybinds remain unchanged

## Theming (initial)

```yaml
font: JetBrainsMono Nerd Font 12
background: "#282828d0"
color: "#fbf1c7"
border: "#8ec07c"
separator: " -> "
border_width: 2
corner_r: 10
padding: 15
anchor: center
```

## Open Items

- [ ] Determine headphone/speaker sink names for audio switching
- [ ] Design host-specific display scale submenu (endeavour vs opportunity vs voyager)
- [ ] Decide whether to remove `Mod+/` keybinds-help.sh or keep as backup
- [ ] Decide whether to remove `Mod+Ctrl+Alt+L` (lock), `Mod+Shift+C` (reload), `Mod+Shift+Q` (quit) now that they're in the Session/Power submenus
