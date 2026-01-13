# Tablet Mode

Provides touchscreen gesture support, auto-rotation, and on-screen keyboard for touchscreen devices.

Currently enabled on: **opportunity** (Framework 12 laptop with touchscreen)

## Components

### lisgd - Gesture Daemon
- Detects multi-finger swipe gestures on touchscreen
- Runs as a systemd user service
- Configured to use stable device path: `/dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event`

### iio-niri - Auto-Rotation
- Monitors accelerometer via iio-sensor-proxy
- Automatically rotates display based on device orientation
- Integrated with niri compositor

### wvkbd - Virtual Keyboard
- Wayland-native on-screen keyboard
- Shows/hides via touch gestures
- Simple start/kill approach for reliable show/hide behavior

## Touch Gestures

| Gesture | Action |
|---------|--------|
| 3-finger swipe left | Switch to previous workspace |
| 3-finger swipe right | Switch to next workspace |
| 3-finger swipe up from bottom | Toggle application launcher |
| 3-finger swipe down from top | Close current window |
| 1-finger swipe up from bottom (short) | Show on-screen keyboard |
| 2-finger swipe down from top | Hide on-screen keyboard |
| 2-finger swipe left | Browser back (Alt+Left) |
| 2-finger swipe right | Browser forward (Alt+Right) |

## Requirements

### System Level
User must be in the `input` group to access touchscreen devices:

```nix
# In users/<username>/nixos.nix
extraGroups = [ "networkmanager" "wheel" "docker" "input" ];
```

**Important:** Group membership changes require logout/login to take effect.

### Hardware
- Touchscreen device with stable `/dev/input/by-path/` identifier
- Accelerometer support for auto-rotation (iio-sensor-proxy)
- Wayland compositor (tested with niri)

## Configuration

### Enabling Tablet Mode

In `flake.nix` for a specific host:

```nix
{
  # System module import
  imports = [
    ./modules/nixos/tablet-mode.nix
  ];

  # Enable system-level support (hardware sensors)
  tablet-mode.enable = true;

  # Home Manager module import
  home-manager.users.jordangarrison.imports = [
    ./modules/home/tablet-mode
  ];
}
```

### Device Path Configuration

If you have different hardware, find your touchscreen device:

```bash
for dev in /dev/input/event*; do
  name=$(cat /sys/class/input/$(basename $dev)/device/name 2>/dev/null || echo "unknown")
  echo "$dev: $name"
done
```

Then update the device path in `default.nix`:

```nix
ExecStart = "${pkgs.lisgd}/bin/lisgd -d /dev/input/by-path/YOUR-DEVICE-PATH ${lib.concatStringsSep " " gestures}";
```

Use the stable path from `/dev/input/by-path/` instead of `/dev/input/eventX` to ensure it persists across reboots.

## Troubleshooting

### Check Service Status

```bash
# Gesture daemon
systemctl --user status lisgd
journalctl --user -u lisgd -f

# Auto-rotation
systemctl --user status iio-niri
journalctl --user -u iio-niri -f
```

### Verify Permissions

```bash
# Check group membership
groups  # Should include 'input'
id      # Check active groups (must logout/login after adding group)

# Check device permissions
ls -la /dev/input/event*  # Should show group 'input' with rw permissions
```

### Common Issues

**lisgd service fails with "Couldn't bind event from dev filesystem"**
- User not in `input` group, or group change not active yet (logout/login required)
- Device path incorrect or doesn't exist
- Device permissions incorrect

**Gestures not responding**
- Check if lisgd service is running: `systemctl --user status lisgd`
- Verify touchscreen device is accessible: `ls -la /dev/input/by-path/`
- Check logs for errors: `journalctl --user -u lisgd -f`

**On-screen keyboard doesn't show**
- Gesture might be captured by another application
- Try manually: `wvkbd-mobintl &`
- Check if wvkbd is already running: `pgrep wvkbd-mobintl`

**Bottom-edge gestures don't work when keyboard is visible**
- This is expected behavior - keyboard captures bottom touches
- Use 2-finger swipe down from top to hide keyboard
- Alternative: tap outside keyboard area if using a different OSK

## Files

- `default.nix` - Main configuration (gestures, services, packages)
- `../../nixos/tablet-mode.nix` - System-level module (hardware sensors)
- `README.md` - This file

## Resources

- [lisgd GitHub](https://github.com/phillipberndt/lisgd) - Gesture daemon
- [iio-niri GitHub](https://github.com/YaLTeR/iio-niri) - Auto-rotation for niri
- [wvkbd GitHub](https://github.com/jjsullivan5196/wvkbd) - Virtual keyboard
