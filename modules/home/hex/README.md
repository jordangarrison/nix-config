# Hex on Linux

Hex is temporarily disabled on endeavour, opportunity, and discovery as of
Nov 18: it holds the microphone and blocks Handy. Disabling removes the package,
`hex.service`, and the Niri Ctrl+Alt+Space binding; downloaded models and user
data stay in `~/.local/share/hex`. To try it again, set the host's
`users.jordangarrison.apps.hex.enable = true` in `flake.nix` and follow the
guarded build → test → approved switch flow. The instructions below apply
when enabled. Handy, Voyager, macOS, and standalone WSL Home Manager are unchanged.

## Ownership and updates

`flake.nix` pins `anomalyco/hex` to **v3.4.0**; `flake.lock` fixes its revision.
The upstream Home Manager module owns the package and `hex.service`, scoped to
`graphical-session.target`. It waits for the session display and uses private
user data at `~/.local/share/hex`. No root daemon or new device permissions.

Hex builds from source with our nixpkgs and follows our Home Manager input.
Using the host nixpkgs keeps glibc compatible with the system graphics drivers.
The package wraps its native libraries, `wl-clipboard`, `wtype`, and ffmpeg.
Update the release tag, run `nix flake update hex`, and rebuild. Do not use the
upstream installer, in-app updater, or a second XDG autostart entry.

## Desktop requirements

- The existing PipeWire/WirePlumber session supplies ALSA compatibility for the
  microphone. Choose the input device in Hex; check routing in `pavucontrol`.
- A working Vulkan driver is required even for the settings window and CPU
  inference. The package supplies the loader, not the system GPU driver.
- Niri supplies layer-shell, clipboard/data-control, and virtual-keyboard
  protocols. Hex copies with `wl-copy` and pastes with `wtype`.
- Niri binds **Ctrl+Alt+Space** directly to `hex dictation toggle` when Hex is
  enabled. The current endeavour portal exposes no GlobalShortcuts interface,
  so dictation does not depend on that portal. No input-device access is needed.
- GNOME uses its GlobalShortcuts portal. The desktop must approve the shortcut;
  its assigned key is shown in Hex under **Desktop shortcuts**. If a future Niri
  portal also offers it, Niri's compositor binding remains the authoritative key.
- GNOME lacks the virtual-keyboard protocol: approve the RemoteDesktop portal
  keyboard-control prompt on first paste. Hex saves the consent token. Without
  approval, the transcript remains on the clipboard for manual paste. GNOME's
  overlay is limited and may use an already running XWayland session; the
  upstream Nix guide's primary tested contract is wlroots-style desktops.
- Hex needs **no** uinput, ydotool, `input` group, udev rule, or capabilities.
  No existing account permissions are changed by this module.

## First use after an approved switch

1. Open **Hex** from the desktop launcher (or run `hex`). The upstream service
   also starts with the graphical session. Do not run it with sudo.
2. Run `hex model install` as Jordan to download the selected `parakeet_v3`
   model (network and user-data disk space required). Models are **not** in the
   Nix store. Builds and activation do not download them. Select another model
   in Nix if desired; `model` is reapplied on activation.
3. On Niri, **Ctrl+Alt+Space** works through the compositor binding. On GNOME,
   approve it in the desktop shortcut dialog if asked. Press once to record,
   again to transcribe. Release modifiers before text arrives.
   This is separate from Handy's **Super+Shift+D** and
   **Super+Ctrl+Alt+Shift+5**; those bindings are unchanged.
4. On GNOME, approve keyboard control at first paste. For terminals, enable
   **Terminal paste** in Hex when Ctrl+Shift+V is required instead of Ctrl+V.
5. Try a short dictation in a native Wayland app and a terminal. Neither real
   microphone capture nor portal consent can be checked by a Nix build.

If GNOME refuses the portal shortcut, inspect Hex's Desktop shortcuts page
and choose a free key. Niri already has a gated binding to `hex dictation toggle`;
no Handy bindings change.
The declared Ctrl+Alt+Space shortcut/mode is reapplied on activation; other
window settings stay writable.

```sh
hex status --json
hex model list
systemctl --user status hex.service
journalctl --user -u hex.service
```

Before a switch, stop any active recording. Use the repository's guarded
build → test → approved switch flow; this change does not apply itself.

Upstream references at the pinned release:
- https://github.com/anomalyco/hex/blob/v3.4.0/docs/nix.md
- https://github.com/anomalyco/hex/blob/v3.4.0/docs/linux.md
- https://github.com/anomalyco/hex/blob/v3.4.0/nix/hm-module.nix
