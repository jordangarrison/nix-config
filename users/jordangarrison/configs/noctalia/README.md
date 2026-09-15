# Noctalia Configuration

This directory contains the shared declarative configuration for Noctalia v5,
the native C++/OpenGL ES shell used by Niri on `endeavour` and `opportunity`.
Noctalia provides the status bar, notification daemon, launcher, emoji search,
clipboard history, lock screen, OSDs, and session controls. `swaybg` remains the
wallpaper owner.

## Configuration ownership

`modules/home/niri/default.nix` imports Noctalia's upstream Home Manager module
and passes `config.toml` to `programs.noctalia.settings`. Home Manager:

- installs the pinned Noctalia package;
- validates the TOML during the build;
- creates the read-only `~/.config/noctalia/config.toml` symlink; and
- manages `noctalia.service` in the user session.

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
noctalia config validate users/jordangarrison/configs/noctalia/config.toml
nh os build . --no-nom -H opportunity
```

Use the Noctalia package pinned by this flake for validation when the active
system still has an older executable. Keep wallpaper rendering disabled here;
Niri starts `swaybg` separately.

## IPC commands

Current integrations use Noctalia v5's canonical message interface:

```bash
noctalia msg panel-toggle launcher
noctalia msg panel-toggle launcher "/emo "
noctalia msg panel-toggle clipboard
noctalia msg session lock
noctalia msg settings-toggle
```

These commands are also used by the Niri bindings, idle locker, tablet launcher
gesture, and wlr-which-key lock action.

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
noctalia config validate ~/.config/noctalia/config.toml
```

Under Niri, Noctalia owns notifications and native clipboard history and
persistence. Hyprland retains its separate mako/clipboard setup.

## Resources

- [Noctalia documentation](https://docs.noctalia.dev/)
- [Noctalia source](https://github.com/noctalia-dev/noctalia)
- [Niri configuration](../../../../modules/home/niri/default.nix)
