# OmniWM

Niri-style scrolling tiling on the work Mac, with the same keys and layout as
`modules/home/niri`. Enable it with `userApps.omniwm.enable` (set in
`flake.nix` for `H952L3DPHH`). The module sets `programs.omniwm` from Home
Manager, which installs the app and runs it from a launchd agent.

## The settings schema is strict

OmniWM rejects all of `settings.toml` and runs with its defaults when:

- a required key is missing,
- an enum value is unknown, or
- `hotkeys` does not list each action id exactly once.

For this reason, `default.nix` writes the complete file, not only the changes.
Its `hotkeyIds` list is the OmniWM 0.7.4 action catalog. Build-time assertions
catch a bind to an unknown id, duplicate ids, and two actions on one chord.
They cannot catch an action that a newer OmniWM release adds. When nixpkgs
updates OmniWM, compare `hotkeyIds` with the release's `ActionCatalog*.swift`
and `website/src/content/docs/config/settings-reference.md`.

If keys stop working after a change, open **Settings > Troubleshooting** in
OmniWM. It reports why it rejected the file.

## Nix owns the file

The file is a symlink into the Nix store. A change in OmniWM's Settings
window cannot be kept: the next `switch` restores the Nix version. Make
changes in `default.nix`.

## Mod key

Hold **Right Command** for Mod. OmniWM's Hyper setting turns it into
Option+Command. Control and Shift are not in the set, so Mod+Shift and
Mod+Ctrl stay distinct, as on niri. Left Option+Command chords also fire.

OmniWM defaults that have no niri equivalent are set to `Unassigned`, so they
do not take Option chords from Emacs and other apps.

## Differences from niri

- OmniWM has no spawn action. The app launchers (Mod+Return, Mod+B, Mod+E,
  Mod+N, Mod+F) are not bound.
- Each action takes one binding, so the arrow-key copies of H/J/K/L are
  dropped.
- Mod+D opens the command palette in place of the which-key menu.
- Mod+Grave toggles the Quake terminal, which has no niri equivalent.

## First launch

1. Grant **Accessibility** and **Input Monitoring** when prompted. OmniWM does
   not start without them. Input Monitoring is also what lets Right Command
   act as Mod.
2. Keep **Displays have separate Spaces** on (System Settings > Desktop &
   Dock > Mission Control).
3. Quit Rectangle, or turn off its shortcuts, so two tools do not move the
   same windows.
4. Turn off Stage Manager: set `WindowManager.GloballyEnabled = false` in
   `hosts/flomac/configuration.nix`.
