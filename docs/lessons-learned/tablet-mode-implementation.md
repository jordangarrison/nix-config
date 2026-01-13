# Lessons Learned: Tablet Mode Implementation

**Date**: 2026-01-12
**Feature**: Touchscreen gesture support, auto-rotation, and on-screen keyboard for Framework 12 laptop
**Status**: Completed and working
**Effort**: ~3 hours (investigation, implementation, debugging, documentation)

## Executive Summary

Implemented tablet mode for the Framework 12 laptop (opportunity host) to enable touchscreen gestures, auto-rotation, and an on-screen keyboard. The implementation faced several challenges related to permissions, device paths, and state management. This document captures the key lessons learned during the process.

## What We Built

### Components
1. **lisgd**: Touchscreen gesture daemon detecting multi-finger swipes
2. **iio-niri**: Auto-rotation daemon using accelerometer data
3. **wvkbd**: Wayland virtual keyboard for touch input
4. **wtype**: Key simulation for browser navigation gestures

### Gestures Implemented
- 3-finger swipes: workspace navigation, launcher, window management
- 1-finger swipe: show keyboard
- 2-finger swipes: browser navigation, hide keyboard

### Architecture
- Two-part module: system-level (hardware) + home-level (services/gestures)
- systemd user services for automatic lifecycle management
- Stable device paths for reliability across reboots

## Critical Lessons Learned

### 1. Permission Debugging Requires Understanding Active vs Configured State

**The Problem**:
Initial implementation failed with cryptic error:
```
lisgd: libinput error: client bug: Invalid path /dev/input/touchscreen
lisgd: Couldn't bind event from dev filesystem
```

**Investigation Steps**:
1. Checked service status: `systemctl --user status lisgd` → crash loop
2. Checked logs: `journalctl --user -u lisgd -n 20` → permission error
3. Checked device permissions: `ls -la /dev/input/event*` → `root:input 660`
4. Checked groups: `groups jordangarrison` → showed `input` ✓
5. Checked active groups: `id` → NO input group! ✗

**The Gotcha**:
- `groups <username>` shows **configured** groups (what WILL apply after login)
- `id` shows **active** groups (what's currently in effect)
- Adding a user to a group does **not** affect active sessions
- Logout/login is **required** for group membership to take effect

**Lesson**: When debugging permissions, always use `id` to check active state, not `groups <username>`. Group membership changes require logout/login.

**Code Pattern**:
```nix
# In users/<username>/nixos.nix
extraGroups = [ "networkmanager" "wheel" "docker" "input" ];
```

**Verification**:
```bash
id  # Should show gid for input (e.g., 57(input))
ls -la /dev/input/event*  # Should show rw for group
```

### 2. Device Paths Must Be Stable, Not Enumerated

**The Problem**:
Hardcoding `/dev/input/event7` worked initially but was unreliable:
- Event numbers are assigned dynamically by the kernel
- Order can change based on device initialization order
- Reboots could change the event number

**Investigation**:
```bash
# Find all input devices
for dev in /dev/input/event*; do
  name=$(cat /sys/class/input/$(basename $dev)/device/name 2>/dev/null)
  echo "$dev: $name"
done

# Output showed:
# /dev/input/event7: ILIT2901:00 222A:5539  (touchscreen)
```

**The Solution**:
Use `/dev/input/by-path/` symlinks:
```bash
ls -la /dev/input/by-path/ | grep i2c_designware.0
# pci-0000:00:15.0-platform-i2c_designware.0-event -> ../event7
```

**Why It Works**:
- Symlinks are based on hardware bus topology
- Bus addresses don't change (PCI, I2C, etc.)
- Stable across reboots and kernel versions

**Lesson**: For hardware devices, always prefer:
1. `/dev/input/by-path/` (based on hardware location)
2. `/dev/input/by-id/` (based on device identifier)
3. Never use `/dev/input/eventX` directly

**Code**:
```nix
ExecStart = "${pkgs.lisgd}/bin/lisgd -d /dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event ...";
```

### 3. Toggle Mechanisms Need Reliable State Tracking

**The Problem**:
wvkbd uses `SIGUSR2` to toggle visibility, but we can't reliably know its current state.

**Evolution of Solutions**:

#### Attempt 1: Simple Toggle
```bash
pkill -USR2 wvkbd || wvkbd &
```
**Issue**: If keyboard is visible, swipe up hides it (confusing UX)

#### Attempt 2: State File Tracking
```bash
STATE_FILE="/tmp/wvkbd-state-$USER"
if [ ! -f "$STATE_FILE" ] || [ "$(cat "$STATE_FILE")" = "hidden" ]; then
  pkill -USR2 wvkbd
  echo "visible" > "$STATE_FILE"
fi
```
**Issues**:
- State file can desync with actual state
- Manual kill doesn't update state file
- Crash doesn't update state file
- Race conditions with multiple gesture triggers

#### Final Solution: Explicit Start/Kill
```bash
showOsk: if ! pgrep wvkbd; then wvkbd & fi
hideOsk: pkill wvkbd
```
**Benefits**:
- No state file needed
- Process existence is the state
- `pgrep` check is atomic and reliable
- Clear semantics: show = start, hide = kill

**Lesson**: Avoid stateful toggles when possible. Use explicit start/stop with process existence as the source of truth. Toggles with hidden state are error-prone.

**Trade-off**: Process start/kill has slight overhead vs signal, but reliability is worth it.

### 4. Build-Time Success ≠ Runtime Success

**The Reality**:
```bash
nh os build .#opportunity  # ✓ Succeeds
nh os switch .#opportunity  # ✓ Activates
# But...
systemctl --user status lisgd  # ✗ Crash loop
```

**Why This Happens**:
- **Build-time**: Checks Nix syntax, type correctness, file existence
- **Runtime**: Checks permissions, device existence, service dependencies

**Examples of Runtime-Only Failures**:
- Permission errors (missing group membership)
- Device path doesn't exist (wrong hardware)
- Service dependencies not met (compositor not started)
- Environment variables not set

**Debugging Workflow**:
```bash
# 1. Check service status
systemctl --user status <service>

# 2. Read logs (live tail)
journalctl --user -u <service> -f

# 3. Test command manually
<exact ExecStart command from service>

# 4. Check environment
systemctl --user show-environment
```

**Lesson**: Always test runtime behavior, even if builds succeed. Use `journalctl` aggressively for debugging. Test manually before wrapping in systemd service.

### 5. systemd User Services Are Powerful But Need Understanding

**Key Patterns**:

#### Lifecycle Integration
```nix
Unit = {
  After = [ "graphical-session.target" ];
  PartOf = [ "graphical-session.target" ];
};
```
- `After`: Start only after graphical session is ready
- `PartOf`: Stop when graphical session stops

#### Restart Policy
```nix
Service = {
  Restart = "on-failure";
  RestartSec = 3;
};
```
- Automatically restart on crashes
- 3-second delay prevents rapid crash loops

#### User vs System Services
- `systemctl --user` manages user services
- Run in user context, user permissions
- Start with user session, stop with logout
- No root required

**Debugging Commands**:
```bash
# Status and basic info
systemctl --user status <service>

# Logs (last N lines)
journalctl --user -u <service> -n 50

# Logs (live tail)
journalctl --user -u <service> -f

# Restart service
systemctl --user restart <service>

# Stop service
systemctl --user stop <service>

# List all user services
systemctl --user list-units --type=service
```

**Lesson**: systemd user services are ideal for user-level daemons. Use `After`/`PartOf` for lifecycle management, `Restart` for reliability. Debug with `journalctl --user`.

### 6. Gesture Edge Cases Matter

**The Problem**:
Bottom-edge gestures (1-finger swipe up to show OSK) don't work when OSK is already visible at the bottom of the screen.

**Why It Happens**:
- OSK window covers bottom 30-40% of screen
- Touch events on OSK go to the keyboard, not lisgd
- lisgd never sees the gesture

**The Solution**:
- Show keyboard: 1-finger swipe up from bottom
- Hide keyboard: 2-finger swipe down from top
- Top edge is always accessible, even when keyboard is visible

**Lesson**: Consider all UI states when designing gestures. Ensure gestures remain accessible when UI elements they control are visible. Use different edges or finger counts for show vs hide.

### 7. Documentation at Multiple Levels Helps Different Audiences

**What We Created**:

1. **ADR** (`docs/adr/004-add-tablet-mode-support.md`)
   - Audience: Developers, future contributors
   - Content: Architecture decisions, alternatives considered, consequences
   - Purpose: Understand *why* decisions were made

2. **CLAUDE.md** (comprehensive agent documentation)
   - Audience: AI agents, new developers
   - Content: Configuration details, troubleshooting, commands
   - Purpose: Working reference for implementation details

3. **README.md** (main project readme)
   - Audience: Users, quick reference
   - Content: Feature list, host descriptions
   - Purpose: High-level overview

4. **Module README** (`modules/home/tablet-mode/README.md`)
   - Audience: Module users, integrators
   - Content: Usage, configuration, requirements
   - Purpose: How to use this specific module

5. **Lessons Learned** (this document)
   - Audience: Team members, future implementers
   - Content: Process, problems encountered, solutions
   - Purpose: Learn from this implementation

**Lesson**: Document at multiple levels. ADRs for decisions, READMEs for usage, lessons learned for process. Each serves a different purpose and audience.

## What Went Well

### Declarative Configuration
- All configuration in Nix files
- Version controlled
- Reproducible
- Build-time validation where possible

### Modular Design
- System module separate from home module
- Can enable per-host easily
- Clear separation of concerns
- Reusable for other touchscreen devices

### systemd Integration
- Automatic startup with graphical session
- Restart on failure
- Clean lifecycle management
- Easy debugging with journalctl

### Comprehensive Testing
- Tested each gesture individually
- Verified service restarts
- Tested across compositor restarts
- Confirmed reliability over time

## What Could Be Improved

### Auto-Detection
- Currently requires manual device path configuration
- Could script device detection on first boot
- Trade-off: complexity vs flexibility

### State Management
- On-screen keyboard uses start/kill approach
- Could explore more sophisticated state tracking
- Trade-off: reliability vs efficiency

### Gesture Discoverability
- No on-screen hints for gestures
- Users must memorize or read documentation
- Could add tutorial or overlay mode

### Hardware Portability
- Device path is Framework 12-specific
- Needs updates for other touchscreen devices
- Could be more generic with auto-detection

## Recommendations for Future Work

### Immediate Improvements
1. Add auto-detection script for touchscreen device
2. Create gesture cheat sheet (visual reference)
3. Add palm rejection configuration
4. Test on other touchscreen devices

### Long-Term Enhancements
1. Per-application gesture profiles
2. GUI for gesture customization
3. Haptic feedback on gesture completion
4. Integration with GNOME/Hyprland (currently niri-focused)
5. Stylus support and stylus-specific gestures

### Code Quality
1. Extract device detection to helper function
2. Add integration tests for gestures
3. Create gesture testing framework
4. Add CI checks for tablet-mode-enabled hosts

## Conclusion

The tablet mode implementation was successful but revealed important lessons about Linux permissions, hardware device stability, state management, and the difference between build-time and runtime validation.

**Key Takeaways**:
1. Always verify active permissions with `id`, not configured with `groups`
2. Use stable device paths (`/dev/input/by-path/`) not enumerated (`eventX`)
3. Avoid stateful toggles; prefer explicit start/stop
4. Test runtime behavior even when builds succeed
5. Document at multiple levels for different audiences

**Most Valuable Debugging Tools**:
- `id` and `groups` for permissions
- `journalctl --user -u <service> -f` for live logs
- `systemctl --user status <service>` for service state
- Manual command execution for isolating issues
- `/dev/input/by-path/` for device discovery

**Time Breakdown**:
- Investigation and research: 45 minutes
- Initial implementation: 30 minutes
- Debugging permissions: 45 minutes
- Fixing device paths: 20 minutes
- OSK state management: 30 minutes
- Testing and validation: 20 minutes
- Documentation: 50 minutes
- **Total**: ~3 hours

The time investment in debugging and documentation was significant but worthwhile. Future implementations on other touchscreen devices should take 30-45 minutes now that these lessons are documented.

## References

- [ADR 004: Add Tablet Mode Support](../adr/004-add-tablet-mode-support.md)
- [Tablet Mode README](../../modules/home/tablet-mode/README.md)
- [CLAUDE.md - Tablet Mode Section](../../CLAUDE.md#tablet-mode-configuration)
- [lisgd Documentation](https://github.com/phillipberndt/lisgd)
- [systemd user services](https://wiki.archlinux.org/title/Systemd/User)
- [Linux input subsystem](https://www.kernel.org/doc/html/latest/input/input.html)
