# Noctalia v5 Migration Plan

## Goal

Replace the pinned Noctalia v4/Quickshell setup with stable Noctalia v5.1.0 for
the shared Niri desktop while preserving current behavior where v5 provides an
equivalent. Validate the migration in isolated NixOS VMs for both supported Niri
hosts without activating or committing the configuration.

The architectural decisions and rationale are recorded in
[`../adr/007-migrate-noctalia-to-v5.md`](../adr/007-migrate-noctalia-to-v5.md).

## Scope

### In scope

- Stable Noctalia v5 flake input and lock data.
- Upstream Home Manager module, package, and systemd user service integration.
- Curated v5 TOML configuration.
- Niri keybindings and idle lock commands.
- Opportunity's tablet launcher gesture.
- The shared which-key lock action.
- Focused Noctalia and Niri documentation.
- Removal of Niri-only clipboard services superseded by Noctalia v5.
- VM builds for `opportunity` and `endeavour`.
- Visual shell verification in a VM where practical.

### Out of scope

- Changing Hyprland's independent shell or clipboard setup.
- Replacing `swaybg`; Noctalia wallpaper rendering remains disabled.
- Redesigning keybindings unrelated to Noctalia.
- Migrating v4 plugins that are not currently enabled.
- Activating with `nh os test` or `nh os switch`.
- Committing or pushing changes.
- Hardware validation for physical monitors, touchscreen gestures, DDC
  brightness, fingerprint authentication, or GPU-specific behavior.

## Target Behavior

| Feature | Intended v5 behavior |
| --- | --- |
| Shell startup | Home Manager-managed `noctalia.service` |
| Theme | Dark built-in Rosé Pine palette |
| Wallpaper | Disabled in Noctalia; existing `swaybg` startup remains authoritative |
| Bar | Floating-style top bar with the current core launcher, workspace, clock, media, tray, notification, battery, volume, brightness, and control-center functions |
| Launcher | `Mod+Space`, usage sorting, categories, and migrated pinned applications |
| Emoji | `Mod+Semicolon` opens the launcher with the `/emo` provider query |
| Clipboard | `Mod+C` opens Noctalia's native clipboard panel |
| Locking | Idle, before-sleep, `Mod+Ctrl+Alt+L`, and which-key use `noctalia msg session lock` |
| Notifications | Noctalia remains the Niri notification daemon |
| Weather | Round Rock, Fahrenheit, weather effects enabled |
| Night light | Enabled with the solar sunrise/sunset schedule derived from the configured location, and the existing temperatures |
| Runtime customization | GUI changes persist in `~/.local/state/noctalia/settings.toml` |

## Implementation Steps

### 1. Update the flake input

- Replace the final-v4 commit pin with
  `github:noctalia-dev/noctalia/v5.1.0`.
- Keep `inputs.nixpkgs.follows = "nixpkgs"` for consistency with the repository's
  package set, accepting that this may bypass upstream's binary cache.
- Update only the Noctalia lock input.
- Inspect `flake.lock` and confirm legacy `noctalia-qs` dependencies disappear.

Commands:

```bash
nix flake lock --update-input noctalia
git diff -- flake.nix flake.lock
```

### 2. Migrate Home Manager integration

In `modules/home/niri/default.nix`:

- Continue importing `inputs.noctalia.homeModules.default`.
- Rename `programs.noctalia-shell` to `programs.noctalia`.
- Enable the upstream systemd user service.
- Supply the v5 TOML file through `programs.noctalia.settings`.
- Leave `checkConfig` enabled so the package validates TOML during builds.
- Remove v4 package-selection and Quickshell-specific service comments where
  the v5 module already provides the package.
- Remove the manually managed v4 JSON and plugin symlinks.

### 3. Build the v5 configuration

Replace the v4 configuration files under
`users/jordangarrison/configs/noctalia/` with a curated `config.toml`.

Translate intent rather than field names:

- Preserve the dark Rosé Pine visual direction.
- Keep Noctalia wallpaper disabled.
- Reconstruct the top bar with equivalent widgets and approximate spacing,
  opacity, radius, and placement.
- Migrate launcher favorites and enable launcher categories/usage sorting.
- Enable native clipboard history and closed-application persistence.
- Preserve notification daemon ownership and approximate toast/OSD styling.
- Preserve weather, location, night-light temperatures, animation speed,
  avatar, and telemetry preference.
- Keep the dock and desktop widgets disabled.
- Do not carry forward obsolete v4 schema keys or empty/default-only settings.
- Remove v4 `settings.json`, `colors.json`, and `plugins.json` after the TOML
  replacement is ready.

Validate directly against the pinned package when useful, in addition to the
Home Manager build-time check:

```bash
noctalia config validate users/jordangarrison/configs/noctalia/config.toml
```

If the active system still provides v4, invoke the v5 package from the flake
instead of trusting the command on `PATH`.

### 4. Replace executable IPC references

Use these canonical v5 commands:

| Intent | Command |
| --- | --- |
| Launcher | `noctalia msg panel-toggle launcher` |
| Emoji search | `noctalia msg panel-toggle launcher "/emo "` |
| Clipboard history | `noctalia msg panel-toggle clipboard` |
| Lock session | `noctalia msg session lock` |
| Settings | `noctalia msg settings-toggle` |

Update runtime references in:

- `modules/home/niri/default.nix`
- `modules/home/tablet-mode/default.nix`
- `modules/home/wlr-which-key/default.nix`

Search the full repository afterward. Historical ADRs and completed plans may
retain old commands as historical evidence; current configuration and focused
operational documentation must not present v4 commands as active instructions.

```bash
rg 'noctalia-shell|ipc call|lockScreen' \
  modules users/jordangarrison/configs/noctalia
```

### 5. Remove redundant Niri clipboard services

- Remove `services.cliphist` from the Niri module.
- Remove `services.wl-clip-persist` from the Niri module.
- Keep packages and Hyprland startup/configuration needed by Hyprland intact.
- Confirm `Mod+C` uses Noctalia's native clipboard panel.

### 6. Update focused documentation

Update:

- `users/jordangarrison/configs/noctalia/README.md`
- `modules/home/niri/CLAUDE.md`

Document:

- Native v5 rather than Quickshell.
- TOML base configuration and mutable state override precedence.
- Home Manager/systemd service ownership.
- Current IPC syntax and troubleshooting commands.
- The need to rebuild after changing the declarative TOML.
- How to inspect or clear a stale GUI override safely.

Do not rewrite historical ADRs or completed implementation plans. ADR 007 records
which older decisions it supersedes.

### 7. Static checks

Before full VM builds:

```bash
nix flake check
nix eval .#nixosConfigurations.opportunity.config.system.build.vm.drvPath
nix eval .#nixosConfigurations.endeavour.config.system.build.vm.drvPath
```

Also inspect:

```bash
git diff --check
git status --short
git diff --stat
git diff -- flake.nix flake.lock modules/home \
  users/jordangarrison/configs/noctalia docs/adr docs/plans
```

### 8. Build both host VMs

Build the laptop/tablet composition first, then the main desktop composition:

```bash
nh os build-vm . --no-nom -H opportunity
nh os build-vm . --no-nom -H endeavour
```

Both commands must include `--no-nom`. Do not substitute `nh os test`, because
that activates the candidate configuration on the current machine.

Expected host-specific caveats:

- `opportunity`: the VM lacks the physical touchscreen and sensor devices, so
  tablet services may report missing hardware. The build still validates the
  launcher gesture's composed command.
- `endeavour`: the VM cannot reproduce the physical multi-monitor layout or DDC
  devices. The build still validates the main desktop module composition.

### 9. Visual VM walkthrough

Run at least one generated VM and select the Niri session. Check:

- `noctalia.service` starts and remains active.
- The bar appears and does not conflict with another notification/tray host.
- `Mod+Space` toggles the launcher.
- `Mod+Semicolon` opens emoji search.
- `Mod+C` opens native clipboard history and copied text appears.
- `Mod+Ctrl+Alt+L` opens the lock screen and authentication unlocks it.
- The settings window opens through `noctalia msg settings-toggle`.
- Notifications and audio/brightness OSDs appear where VM support permits.
- Wallpaper remains owned by `swaybg`.

Useful diagnostics inside the VM:

```bash
systemctl --user status noctalia.service
journalctl --user -u noctalia.service -b --no-pager
noctalia msg status
noctalia msg --help
noctalia config validate
```

Record any VM-only limitations separately from actual migration failures.

## Completion Criteria

- [ ] Flake resolves Noctalia v5.1.0 with no legacy Quickshell input.
- [ ] Home Manager uses `programs.noctalia` and `noctalia.service`.
- [ ] The curated TOML passes v5 validation without migration warnings.
- [ ] All executable Noctalia IPC references use `noctalia msg`.
- [ ] Niri no longer starts duplicate clipboard history/persistence services.
- [ ] Focused documentation describes v5 accurately.
- [ ] `opportunity` VM builds successfully with `--no-nom`.
- [ ] `endeavour` VM builds successfully with `--no-nom`.
- [ ] Visual VM checks are completed or blocked limitations are documented.
- [ ] No system activation, commit, or push occurred.

## Rollback

Before activation, rollback is simply discarding the migration diff. If a later
approved activation reveals a regression, restore the previous flake input,
Home Manager module namespace, v4 JSON configuration, IPC commands, and Niri
clipboard services, rebuild, and follow the repository's guarded activation
procedure. Do not attempt to run v4 commands against the v5 process or reuse v5
state as v4 configuration.
