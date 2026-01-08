# ADR 003: Add Niri Scrolling Compositor

## Status

Accepted

## Date

2025-01-07

## Context

The current desktop environment options include GNOME and Hyprland. While Hyprland provides excellent tiling capabilities, there's interest in exploring alternative window management paradigms. Niri offers a unique "scrollable tiling" approach where windows are arranged in columns on an infinite horizontal strip, rather than the traditional grid-based tiling.

### Current State
- **GNOME**: Primary DE with extensive customization (workspaces, extensions, keybindings)
- **Hyprland**: Tiling WM with vim-style navigation, used as alternative session
- **Both available**: Selectable at GDM login screen

### Why Niri?
1. **Scrollable layout**: Windows arrange horizontally without resizing existing windows
2. **Simpler mental model**: No complex tree layouts to manage
3. **Built-in features**: Screenshot UI, gestures, animations without external tools
4. **Wayland-native**: Modern compositor with good multi-monitor support
5. **Active development**: Regular releases, responsive maintainer

## Decision

Add niri as a third desktop environment option on the endeavour workstation, using the niri-flake for NixOS integration. The configuration will:

1. Use declarative Nix configuration via `programs.niri.settings`
2. Mirror Hyprland keybindings for muscle memory consistency
3. Reuse existing supporting tools (waybar, mako, walker, etc.)
4. Keep Hyprland and GNOME available as fallback options

## Architecture Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Config method | `programs.niri.settings` (Nix) | Build-time validation, type-checked |
| Package | `niri-unstable` | Latest features, scrolling improvements |
| Wallpaper | swaybg | Simple, reliable, Sway-compatible |
| Lock screen | swaylock | Sway-compatible, well-tested |
| Idle | swayidle | Sway-compatible, integrates with swaylock |
| Bar | waybar | Already configured for Hyprland, works with niri |
| Launcher | walker | Already configured, Wayland-native |
| Notifications | mako | Already configured, Wayland-native |
| Screenshots | grim + slurp + satty | Already configured, Wayland-native |
| Clipboard | cliphist + wl-clipboard | Already configured, Wayland-native |
| XWayland | xwayland-satellite | Niri's recommended XWayland solution |
| Auth agent | polkit-kde-agent | Bundled by niri-flake, Qt-based |

## Implementation

### Files Created

```
modules/nixos/niri-desktop.nix     # System-level niri configuration
modules/home/niri/default.nix      # User-level settings and keybindings
```

### Module Structure

#### System Module (`modules/nixos/niri-desktop.nix`)
- Imports `niri.nixosModules.niri` from niri-flake
- Applies `niri.overlays.niri` for package access
- Enables `programs.niri` with `niri-unstable` package
- Installs system packages: xwayland-satellite, swaybg, swaylock, swayidle

#### Home Module (`modules/home/niri/default.nix`)
- User packages for desktop environment
- `programs.niri.settings` with full configuration:
  - Input settings (keyboard, touchpad, mouse)
  - Output/monitor configuration (host-specific)
  - Layout settings (gaps, focus ring, shadows)
  - Startup programs
  - Keybindings
  - Window rules
  - Animations

### Keybinding Mapping

Keybindings mirror Hyprland for consistency:

| Function | Hyprland | Niri |
|----------|----------|------|
| Terminal | `Super+Return` | `Mod+Return` |
| Close window | `Super+Q` | `Mod+Q` |
| App launcher | `Super+Space` | `Mod+Space` |
| Focus left/right | `Super+H/L` | `Mod+H/L` |
| Focus up/down | `Super+K/J` | `Mod+K/J` |
| Move window | `Super+Shift+H/J/K/L` | `Mod+Shift+H/J/K/L` |
| Workspace 1-10 | `Super+1-0` | `Mod+1-0` |
| Move to workspace | `Super+Shift+1-0` | `Mod+Shift+1-0` |
| Toggle floating | `Super+V` | `Mod+V` |
| Maximize | `Super+M` | `Mod+M` |
| Focus monitor | `Super+,/.` | `Mod+,/.` |

#### Niri-specific bindings
| Function | Binding |
|----------|---------|
| Toggle overview | `Mod+Tab` |
| Consume into column | `Mod+Ctrl+H` |
| Expel from column | `Mod+Ctrl+L` |
| Toggle tabbed | `Mod+T` |
| Cycle column width | `Mod+R` |
| Resize column | `Mod+Minus/Equal` |

### Monitor Configuration (endeavour)

```nix
outputs = {
  "DP-3" = {
    mode = { width = 3840; height = 2160; refresh = 60.0; };
    scale = 1.5;
    position = { x = 0; y = 0; };
  };
  "DP-4" = {
    mode = { width = 2560; height = 1440; refresh = 60.0; };
    scale = 1.333;
    position = { x = 2560; y = 0; };
    transform.rotation = 270;  # Portrait
  };
};
```

### Flake Integration

```nix
# flake.nix inputs
inputs.niri.url = "github:sodiboo/niri-flake";

# endeavour modules
modules = [
  ./modules/nixos/niri-desktop.nix
  # ...
  {
    home-manager.users.jordangarrison.imports = [ ./modules/home/niri ];
  }
];
```

## Consequences

### Positive
- Third desktop environment option for experimentation
- Consistent keybindings across Hyprland and niri
- Declarative, version-controlled configuration
- Build-time validation prevents invalid configs
- Binary cache available for faster builds

### Negative
- Additional ~400MB disk space for niri and dependencies
- Learning curve for niri-specific concepts (scrolling, columns)
- Configuration changes require rebuild (unlike Hyprland's live reload)
- Some tools (hyprpaper, hyprlock, hypridle) replaced with Sway equivalents

### Neutral
- Niri is still relatively new compared to Hyprland/Sway
- Scrolling paradigm may or may not suit workflow
- Can always fall back to Hyprland or GNOME

## Testing Checklist

- [x] `nix flake check` passes
- [x] `nh os build .` succeeds
- [x] `nh os test .` activates successfully
- [ ] Niri session appears in GDM
- [ ] Keybindings work as expected
- [ ] Multi-monitor layout correct
- [ ] Waybar displays properly
- [ ] Walker launcher works
- [ ] Screenshots work
- [ ] Lock screen works
- [ ] Media keys work

## Future Considerations

1. **Expand to other hosts**: Currently endeavour only; can enable on opportunity/voyager later
2. **Custom waybar config**: May want niri-specific waybar modules
3. **Theming**: Could add stylix integration for consistent theming
4. **Monitor configs**: Add host-specific monitor configurations for other machines

## References

- [niri GitHub](https://github.com/YaLTeR/niri)
- [niri-flake](https://github.com/sodiboo/niri-flake)
- [niri-flake docs](https://github.com/sodiboo/niri-flake/blob/main/docs.md)
- [NixOS Wiki - Niri](https://wiki.nixos.org/wiki/Niri)
