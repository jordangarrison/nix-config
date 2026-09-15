# ADR 007: Migrate Noctalia Shell to v5

## Status

Accepted

## Date

2026-09-15

## Context

The Niri desktop currently uses the final v4 generation of Noctalia Shell. The
flake is pinned to a v4 `noctalia-shell` commit, Home Manager configures
`programs.noctalia-shell`, and the shell reads several JSON files through
out-of-store symlinks. Niri keybindings, idle locking, the tablet launcher
gesture, and the which-key lock action all use the v4
`noctalia-shell ipc call ...` interface.

Noctalia v5 is a ground-up native C++/OpenGL ES implementation rather than an
in-place Quickshell upgrade. It has a different package and executable, Home
Manager option namespace, TOML configuration model, IPC interface, and native
clipboard implementation. Upstream does not migrate v4 JSON configuration.

Noctalia v5.1.0 is the current stable release. Continuing to use v4 leaves the
desktop on an obsolete architecture and prevents adoption of the supported v5
configuration and IPC interfaces.

## Decision

Migrate the shared Niri shell configuration to Noctalia v5.1.0 with the
following architecture:

1. Pin the flake input to the stable `github:noctalia-dev/noctalia/v5.1.0`
   release rather than tracking the development branch.
2. Import `inputs.noctalia.homeModules.default` and configure
   `programs.noctalia` through Home Manager.
3. Let the upstream Home Manager module own the `noctalia.service` user unit,
   package installation, build-time configuration validation, and
   `~/.config/noctalia/config.toml`.
4. Express the curated, version-controlled base configuration as v5 TOML.
   Noctalia may keep mutable GUI overrides in
   `~/.local/state/noctalia/settings.toml`, which intentionally take precedence
   over the declarative base.
5. Preserve the existing user experience where v5 has a direct equivalent,
   including the Rosé Pine appearance, bar organization, launcher favorites,
   external `swaybg` wallpaper ownership, notifications, OSD, weather, night
   light, and familiar keybindings.
6. Replace v4 IPC calls with the canonical `noctalia msg ...` commands.
7. Use Noctalia v5's native clipboard history and clipboard persistence in the
   Niri session instead of running parallel `cliphist` and `wl-clip-persist`
   services. Hyprland retains its independent clipboard setup.
8. Validate host integration with NixOS VMs for both `opportunity` and
   `endeavour`. Do not activate the candidate configuration on the current
   system during migration testing.

## IPC Mapping

| Behavior | v4 | v5 |
| --- | --- | --- |
| Launcher | `noctalia-shell ipc call launcher toggle` | `noctalia msg panel-toggle launcher` |
| Emoji search | `noctalia-shell ipc call launcher emoji` | `noctalia msg panel-toggle launcher "/emo "` |
| Clipboard history | `noctalia-shell ipc call launcher clipboard` | `noctalia msg panel-toggle clipboard` |
| Lock session | `noctalia-shell ipc call lockScreen lock` | `noctalia msg session lock` |
| Settings | `noctalia-shell ipc call settings toggle` | `noctalia msg settings-toggle` |

The emoji command opens the launcher with the v5 emoji provider's default
`/emo` query because v5 does not expose the v4 dedicated emoji IPC action.

## Configuration Ownership

Noctalia v5 merges configuration in this order:

1. Built-in defaults.
2. Home Manager's declarative `~/.config/noctalia/config.toml`.
3. Noctalia-managed `~/.local/state/noctalia/settings.toml` overrides.

The repository TOML is the portable base configuration. Settings changed in the
Noctalia UI remain mutable and survive rebuilds, but they are host-local until
exported and deliberately incorporated into the repository configuration. This
replaces v4's writable out-of-store JSON symlinks and avoids making a
Nix-managed file writable.

## Alternatives Considered

### Continue using pinned v4

Rejected. It avoids immediate migration work but retains an obsolete
Quickshell implementation and unsupported interfaces.

### Track the v5 development branch

Rejected. The desktop shell is a core session component, so a stable release
pin is preferable to unreviewed changes from the default branch.

### Keep live out-of-store configuration symlinks

Rejected. The v5 Home Manager module provides configuration generation,
validation, restart triggers, and a deliberate mutable override layer. Using
that supported model gives stronger validation and clearer ownership.

### Keep cliphist and wl-clip-persist alongside Noctalia

Rejected for Niri. Noctalia v5 directly owns clipboard history and preservation;
running duplicate clipboard watchers and persistence owners adds unnecessary
state and may produce conflicting behavior. Hyprland remains unaffected because
its clipboard integration is separate.

### Validate by activating with `nh os test`

Rejected for the migration phase. `nh os test` changes the active system, even
though it does not make the generation the boot default. VM builds and visual
VM testing provide isolation from the working desktop.

## Consequences

### Positive

- Uses the supported stable Noctalia architecture and IPC.
- Gains build-time TOML validation through Home Manager.
- Removes duplicate Niri clipboard services.
- Keeps runtime GUI customization possible through v5's state layer.
- Tests both target host compositions without replacing the active system.

### Negative

- v4 JSON settings cannot be mechanically migrated; some settings have no exact
  v5 equivalent and require judgment.
- Existing v4 GUI state is not reused.
- GUI changes are no longer written directly into the Git worktree.
- A VM can validate composition and shell behavior but cannot reproduce
  host-specific monitor layouts, touchscreen hardware, brightness devices, or
  GPU behavior exactly.

## Validation

The implementation must:

1. Pass Noctalia's configuration validator through the Home Manager build.
2. Contain no executable v4 `noctalia-shell ipc call` references.
3. Build isolated NixOS VMs for both hosts:

   ```bash
   nh os build-vm . --no-nom -H opportunity
   nh os build-vm . --no-nom -H endeavour
   ```

4. Visually test at least one VM for Noctalia service startup, bar rendering,
   launcher, emoji search, clipboard panel, settings, notifications, and lock
   screen behavior.

No `switch`, `test`, commit, or push is part of this migration without separate
approval.

## Superseded Documentation

This decision supersedes the Noctalia and Niri clipboard implementation details
recorded in ADR 003 and the Noctalia launcher command recorded in ADR 004. Those
ADRs remain unchanged as historical records of the architecture at the time.
