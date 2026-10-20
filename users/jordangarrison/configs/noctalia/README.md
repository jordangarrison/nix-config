# Noctalia Configuration

This directory contains the shared declarative configuration for Noctalia v5,
the native C++/OpenGL ES shell used by Niri on `endeavour` and `opportunity`.
Noctalia provides the status bar, notification daemon, launcher, emoji search,
clipboard history, lock screen, OSDs, and session controls. `swaybg` remains the
wallpaper owner.

## Configuration ownership

`modules/home/niri/default.nix` enables Home Manager's own `programs.noctalia`
module, sets its package from the `noctalia` flake input, and passes
`config.toml` to `programs.noctalia.settings`. It does not import the flake's
Home Manager module: that module replaces Home Manager's through hard-coded
`disabledModules` paths, which broke evaluation once already. Home Manager:

- installs the pinned Noctalia package;
- validates the TOML during the build;
- creates the read-only `~/.config/noctalia/config.toml` symlink; and
- manages `noctalia.service` in the user session.

The Niri module adds `ConditionEnvironment=XDG_CURRENT_DESKTOP=niri` to that
unit, so a GNOME login on the same host skips Noctalia instead of running it
headless next to GNOME Shell.

Noctalia merges settings in this order:

1. built-in defaults;
2. the repository's declarative `config.toml`; and
3. mutable GUI overrides in `~/.local/state/noctalia/settings.toml`.

The state file intentionally wins. Settings changed in the GUI persist locally,
but are not written back to this repository or shared with other hosts.

## Changing the shared configuration

Edit `config.toml`, validate it, and rebuild the affected host. Unlike the old
v4 out-of-store JSON setup, repository edits do not take effect until a Home
Manager/NixOS rebuild installs the generated configuration.

```bash
nh os build . --no-nom -H opportunity
```

The build runs `noctalia config validate` with the pinned package. To validate
without a full build, or when the installed executable is older, use the
pinned package directly:

```bash
noctalia="$(nix build --no-link --print-out-paths \
  .#nixosConfigurations.opportunity.config.home-manager.users.jordangarrison.programs.noctalia.package)/bin/noctalia"
"$noctalia" config validate users/jordangarrison/configs/noctalia/config.toml
```

The validator accepts any string for many keys (`weather.unit = "fahrenheit"`
once passed and silently meant metric), so check a new key's consumer in the
Noctalia source. Keep wallpaper rendering disabled here; Niri starts `swaybg`
separately.

Pin every value you care about, including one that equals today's v5 default.
An unpinned preference follows upstream's defaults, which change between
releases: v5.2 turned UI sounds and lock-screen transitions on. Leave
out keys you have no preference on, and say in a comment why a pin exists when
the reason is not obvious. Behaviors that v5 cannot reproduce — notification
toast durations, low-urgency history, hover-only bar labels, and the seventh
control center shortcut — and the hibernate action that was not carried over
are recorded in [ADR 007](../../../../docs/adr/007-migrate-noctalia-to-v5.md).

## Testing in a VM

`run-noctalia-vm.sh [endeavour|opportunity]` at the repository root builds the
host as a test-only VM with Niri autologin and a virgl GPU, then launches it
without touching the running system. The disk image persists in
`/tmp/noctalia-<host>.qcow2`; delete it to test a fresh state directory. Set
VM memory through `virtualisation.vmVariant.virtualisation.memorySize` in the
script, not a QEMU `-m` flag, which aborts startup.

## IPC commands

Current integrations use Noctalia v5's canonical message interface:

```bash
noctalia msg panel-toggle launcher
noctalia msg panel-toggle launcher "/emo "
noctalia msg panel-toggle clipboard
noctalia msg session lock
noctalia msg settings-toggle
```

These commands are also used by the Niri bindings, the swayidle locker (every
Niri host except `endeavour`), the tablet launcher gesture, and the
wlr-which-key lock action.

## Runtime overrides

To see whether the GUI is overriding a declarative value, inspect:

```bash
less ~/.local/state/noctalia/settings.toml
```

To test the base configuration without deleting local changes, stop Noctalia,
move the override aside, and start it again:

```bash
systemctl --user stop noctalia.service
mv ~/.local/state/noctalia/settings.toml \
  ~/.local/state/noctalia/settings.toml.backup
systemctl --user start noctalia.service
```

Restore the backup if needed. Incorporate intentional settings into
`config.toml` explicitly rather than editing the Nix-managed symlink.

## Troubleshooting

```bash
systemctl --user status noctalia.service
journalctl --user -u noctalia.service -b --no-pager
noctalia msg status
noctalia msg --help
noctalia config validate        # base TOML plus settings.toml overrides
noctalia config export merged   # effective user settings
```

Pass a path to `config validate` only to check that one file; it then ignores
`settings.toml`.

A status of `start condition unmet` means the session is not Niri; that is the
expected result under GNOME.

Under Niri, Noctalia owns notifications and native clipboard history and
persistence. It also always registers a NetworkManager secret agent (Wi-Fi
and 802.1x only) and a BlueZ pairing agent next to `nm-applet` and
`blueman-applet`. NetworkManager falls through to `nm-applet` for secrets
Noctalia does not handle, and BlueZ uses whichever agent registered as default
last. The Hyprland configuration, not enabled on any host, keeps its own
mako and cliphist setup.

## Resources

- [Noctalia documentation](https://docs.noctalia.dev/)
- [Noctalia source](https://github.com/noctalia-dev/noctalia)
- [Niri configuration](../../../../modules/home/niri/default.nix)
