# ADR 004: Add Tablet Mode Support

## Status

Accepted

## Date

2026-01-12

## Context

The Framework 12 laptop (opportunity host) has a touchscreen display but lacks gesture support, auto-rotation, and an on-screen keyboard out of the box. This limits its usability in tablet-like scenarios where touch interaction is preferred over keyboard/mouse.

### Current State
- **opportunity**: Framework 12 laptop with touchscreen hardware
- **Desktop environments**: GNOME, Hyprland, and Niri available
- **Input methods**: Physical keyboard and touchpad only
- **Display orientation**: Fixed, no auto-rotation

### Requirements
1. **Touchscreen gestures**: Multi-finger swipes for workspace navigation, window management, and application launching
2. **Auto-rotation**: Automatic display rotation based on device orientation
3. **On-screen keyboard**: Virtual keyboard for text input without physical keyboard
4. **Reliability**: Gestures must work consistently across compositor restarts
5. **User permissions**: Secure access to input devices without compromising system security

## Decision

Implement tablet mode using three components that integrate with the existing Wayland compositor (niri):

1. **lisgd** - Touchscreen gesture daemon for detecting multi-finger swipes
2. **iio-niri** - Auto-rotation daemon using accelerometer data
3. **wvkbd** - Wayland virtual keyboard for on-screen input

The configuration will be modular, allowing it to be enabled per-host in the flake configuration.

## Architecture Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Gesture daemon | lisgd | Lightweight, flexible gesture syntax, libinput-based |
| Auto-rotation | iio-niri | Native niri integration, uses iio-sensor-proxy |
| Virtual keyboard | wvkbd | Wayland-native, simple, gesture-controlled |
| Key simulation | wtype | Wayland key injection for browser navigation |
| Device path | `/dev/input/by-path/*` | Stable across reboots (vs `/dev/input/eventX`) |
| OSK control | Start/kill processes | Reliable show/hide vs unreliable toggle signals |
| Permissions | `input` group membership | Standard Linux approach for device access |
| Service management | systemd user services | Automatic start, restart on failure, user-level |

### Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| **touchegg** | GUI configuration | X11-only, not Wayland-compatible | Rejected |
| **libinput-gestures** | Popular, well-maintained | Requires external tools, less flexible | Rejected |
| **fusuma** | Ruby-based, easy config | Heavy dependency chain, Ruby overhead | Rejected |
| **SIGUSR2 toggle for OSK** | Simple single signal | Unreliable state tracking, race conditions | Rejected |
| **State file for OSK** | Tracks visibility state | Complexity, sync issues with actual state | Rejected |
| **Start/kill OSK** | Simple, reliable | Process overhead on show/hide | **Accepted** |

## Implementation

### Files Created

```
modules/nixos/tablet-mode.nix          # System-level module (hardware sensors)
modules/home/tablet-mode/default.nix   # User-level services and gestures
modules/home/tablet-mode/README.md     # Module documentation
docs/adr/004-add-tablet-mode-support.md  # This ADR
```

### Module Structure

#### System Module (`modules/nixos/tablet-mode.nix`)
```nix
{
  options.tablet-mode.enable = mkEnableOption "tablet mode support";

  config = mkIf cfg.enable {
    hardware.sensor.iio.enable = true;  # Accelerometer support
  };
}
```

**Purpose**: Enable hardware sensor support for auto-rotation

#### Home Module (`modules/home/tablet-mode/default.nix`)
- Packages: lisgd, iio-niri, wvkbd, wtype
- Scripts: showOsk, hideOsk
- Gesture definitions (lisgd format)
- systemd user services for lisgd and iio-niri

### Gesture Configuration

**lisgd syntax**: `-g 'nfingers,gesture,edge,distance,actmode,command'`

| Gesture | Command | Purpose |
|---------|---------|---------|
| 3-finger swipe left | `niri msg action focus-workspace-down` | Previous workspace |
| 3-finger swipe right | `niri msg action focus-workspace-up` | Next workspace |
| 3-finger swipe up (bottom) | `noctalia-shell ipc call launcher toggle` | App launcher |
| 3-finger swipe down (top) | `niri msg action close-window` | Close window |
| 1-finger swipe up (bottom, short) | `showOsk` | Show keyboard |
| 2-finger swipe down (top) | `hideOsk` | Hide keyboard |
| 2-finger swipe left | `wtype -M alt -k Right -m alt` | Browser forward |
| 2-finger swipe right | `wtype -M alt -k Left -m alt` | Browser back |

### User Permissions

**Challenge**: Input devices (`/dev/input/event*`) are owned by `root:input` with `660` permissions.

**Solution**: Add user to `input` group:
```nix
# users/jordangarrison/nixos.nix
extraGroups = [ "networkmanager" "wheel" "docker" "input" ];
```

**Critical requirement**: Group membership changes require logout/login to take effect.

### Device Path Resolution

**Problem**: `/dev/input/eventX` numbers change across reboots, breaking hardcoded paths.

**Solution**: Use stable `/dev/input/by-path/` symlinks:
```nix
ExecStart = "${pkgs.lisgd}/bin/lisgd -d /dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event ...";
```

**Discovery command**:
```bash
for dev in /dev/input/event*; do
  name=$(cat /sys/class/input/$(basename $dev)/device/name 2>/dev/null)
  echo "$dev: $name"
done | grep -i touch
```

### On-Screen Keyboard Control

**Evolution of approach**:

1. **Initial**: Toggle signal (`pkill -USR2 wvkbd`)
   - **Issue**: No state tracking, unreliable show/hide

2. **State file**: Track visibility in `/tmp/wvkbd-state-$USER`
   - **Issue**: State file out of sync with actual visibility

3. **Final**: Start process to show, kill process to hide
   - **Benefit**: Reliable, simple, no state tracking needed
   ```bash
   showOsk: if ! pgrep wvkbd; then wvkbd-mobintl & fi
   hideOsk: pkill wvkbd-mobintl
   ```

### systemd Integration

Both services use similar patterns:

```nix
systemd.user.services.lisgd = {
  Unit = {
    Description = "Touchscreen gesture daemon";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "...";
    Restart = "on-failure";
    RestartSec = 3;
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

**Benefits**:
- Automatic start with graphical session
- Auto-restart on failure (3-second delay)
- User-level services (no root required)
- Integration with session lifecycle

### Flake Integration

```nix
# flake.nix - opportunity host configuration
{
  imports = [
    ./modules/nixos/tablet-mode.nix
  ];

  tablet-mode.enable = true;

  home-manager.users.jordangarrison.imports = [
    ./modules/home/tablet-mode
  ];
}
```

## Consequences

### Positive
- Full touchscreen gesture support on Framework 12 laptop
- Auto-rotation works seamlessly with niri compositor
- On-screen keyboard available when needed
- Gestures mirror common tablet patterns (swipes for navigation)
- Modular design allows easy enabling on other touchscreen devices
- Declarative configuration in Nix
- Services auto-restart on failure
- Stable device paths prevent boot-to-boot issues

### Negative
- Additional packages (~20MB total: lisgd, iio-niri, wvkbd, wtype)
- Requires `input` group membership (security consideration)
- Device path must be determined per-hardware (not auto-detected)
- Logout/login required after adding `input` group
- On-screen keyboard show/hide requires process start/kill (minor overhead)
- Gestures from bottom edge don't work when OSK visible (expected behavior)

### Neutral
- Tablet mode only useful on touchscreen devices (opportunity only currently)
- Auto-rotation may be disruptive in some scenarios (can disable iio-niri service)
- Learning curve for gesture patterns

## Lessons Learned

### Permission Issues are Critical
- **Problem**: Initial implementation crashed with "couldn't bind event from dev filesystem"
- **Root cause**: Missing `input` group membership
- **Diagnostic**: `id` command shows active groups, `groups <user>` shows configured groups
- **Solution**: Add to extraGroups AND logout/login
- **Lesson**: Always verify active permissions with `id`, not just configuration

### Device Paths Must Be Stable
- **Problem**: `/dev/input/event7` works, but number changes on reboot
- **Solution**: Use `/dev/input/by-path/pci-0000:...-event` symlink
- **Lesson**: For hardware devices, always prefer `/dev/*/by-path/` or `/dev/*/by-id/`

### Toggle Signals Are Unreliable
- **Problem**: `pkill -USR2` toggles visibility, but state gets out of sync
- **Attempted fix**: Track state in `/tmp/wvkbd-state-$USER` file
- **Final solution**: Kill to hide, start to show (simple and reliable)
- **Lesson**: Avoid stateful toggles when simple start/kill works

### Systemd User Services Are Powerful
- **Benefit**: Auto-start, restart on failure, lifecycle management
- **Pattern**: `After` + `PartOf` graphical-session.target
- **Debugging**: `systemctl --user status`, `journalctl --user -u <service> -f`
- **Lesson**: Use systemd user services for user-level daemons

### Build-Time vs Runtime Errors
- **Build-time**: Syntax errors, invalid Nix caught immediately
- **Runtime**: Permission errors, device path issues only appear after boot
- **Debugging tools**:
  - `journalctl --user -u <service> -f` for live logs
  - `systemctl --user status <service>` for current state
  - Manual command execution for quick testing
- **Lesson**: Test runtime behavior even if build succeeds

## Testing Checklist

- [x] `nix flake check` passes
- [x] `nh os build .#opportunity` succeeds
- [x] `nh os switch .#opportunity` activates successfully
- [x] User in `input` group after logout/login
- [x] lisgd service running without errors
- [x] iio-niri service running without errors
- [x] 3-finger workspace navigation works
- [x] 3-finger app launcher works
- [x] 3-finger close window works
- [x] 1-finger show OSK works
- [x] 2-finger hide OSK works
- [x] 2-finger browser navigation works
- [x] Auto-rotation works when device rotated
- [x] Services restart on failure
- [x] Gestures work after compositor restart

## Future Considerations

1. **Auto-detect touchscreen device**: Script to find touch-capable device on first boot
2. **Per-application gesture profiles**: Different gestures for specific applications
3. **Gesture customization UI**: GUI for non-technical users to configure gestures
4. **Expand to other hosts**: Enable on any touchscreen device (tablets, 2-in-1s)
5. **Integration with GNOME/Hyprland**: Currently niri-focused, could expand
6. **Haptic feedback**: Vibration on gesture completion (if hardware supports)
7. **Palm rejection**: Ignore accidental palm touches while typing
8. **Stylus support**: Separate stylus gestures and tools

## References

- [lisgd GitHub](https://github.com/phillipberndt/lisgd)
- [iio-niri GitHub](https://github.com/YaLTeR/iio-niri)
- [wvkbd GitHub](https://github.com/jjsullivan5196/wvkbd)
- [wtype GitHub](https://github.com/atx/wtype)
- [iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy)
- [Framework Laptop - NixOS Wiki](https://wiki.nixos.org/wiki/Framework_Laptop_13)
