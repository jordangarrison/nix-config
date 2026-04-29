# Dendritic Nix Migration Design

**Date:** 2026-04-28
**Status:** Draft

## Summary

Migrate this nix-config repository from the current monolithic `flake.nix` layout (5 host blocks, ~430 lines, all module lists hand-maintained per host) to the dendritic pattern using the [Den library](https://github.com/vic/den). End state: `flake.nix` is a thin auto-generated stub; all configuration lives as self-registering modules under `modules/`; aspects compose hosts and users explicitly through Den's `includes` graph.

## Goals

- Eliminate per-host module lists in `flake.nix`. Hosts assemble themselves by listing aspects.
- Make adding a new aspect (service, desktop component, hardware feature) a single-file change.
- Make adding a new host a composition exercise, not a copy-paste of every other host's module list.
- Co-locate flake input declarations with the modules that use them via `flake-file`.
- Preserve every current behavior: 4 NixOS hosts (endeavour, opportunity, voyager, discovery), 1 darwin host (flomac), 1 home-manager-only config (jordangarrison@normandy), 4 users (jordangarrison, mikayla, jane, isla), all current overlays, all current self-hosted services on endeavour.

## Non-goals

- Per-host pruning of `flake.lock`. Lock file remains unified across the flake. Per-host fetch laziness is already provided by Nix; that doesn't change.
- Splitting the repo into multiple flakes.
- Adopting Den's aspect API at fine-grained levels initially. Coarse aspects (≈ 1:1 with current `modules/nixos/*.nix` files) come first; further decomposition is on-demand.
- Migrating away from `nh` CLI; build/test/switch commands stay the same.

## Architecture

### Stack

- **flake-parts** — flake output composition (already a Den dependency)
- **import-tree** (vic/import-tree) — auto-loads every `.nix` file under `modules/` as a flake-parts module; underscore-prefixed paths skipped
- **Den** (vic/den) — provides `den.aspects`, `den.hosts`, `den.homes`, `den.default`, `den.ctx`, `den.provides`
- **flake-file** (vic/flake-file) — auto-regenerates `flake.nix` from inline `flake-file.inputs.<name>` declarations across modules

### Top-level entry point

`flake.nix` becomes auto-generated and minimal. Source of truth for inputs lives in modules. Regenerate with `nix run .#write-flake`.

```nix
# flake.nix (auto-generated)
{
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules);

  inputs = {
    den.url = "github:vic/den";
    flake-file.url = "github:vic/flake-file";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # ... plus any input declared by an aspect via flake-file.inputs
  };
}
```

### Bootstrap modules

```nix
# modules/dendritic.nix — wires Den + flake-file
{ inputs, ... }:
{
  imports = [
    inputs.flake-file.flakeModules.dendritic
    inputs.den.flakeModules.dendritic
  ];

  flake-file.inputs = {
    den.url = "github:vic/den";
    flake-file.url = "github:vic/flake-file";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
  };
}
```

```nix
# modules/defaults.nix — global Den configuration
{ lib, den, ... }:
{
  den.default.nixos.system.stateVersion = "25.11";
  den.default.homeManager.home.stateVersion = "25.11";

  # Enable home-manager class on users by default; per-user opt-out is explicit.
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  # Enable mutual host<->user provision so host aspects can forward HM config to their users.
  den.ctx.user.includes = [ den.provides.mutual-provider ];
}
```

## Directory layout

```
nix-config/
├── flake.nix                              # auto-generated stub (from flake-file)
├── modules/
│   ├── _meta/                             # underscore prefix → skipped by import-tree
│   ├── dendritic.nix                      # Den + flake-file bootstrap
│   ├── defaults.nix                       # den.default + den.ctx + den.schema
│   ├── aspects/
│   │   ├── common.nix                     # base every NixOS host gets
│   │   ├── desktop/
│   │   │   ├── gnome.nix
│   │   │   ├── niri.nix
│   │   │   ├── hyprland.nix
│   │   │   └── tablet-mode.nix            # includes desktop-niri
│   │   ├── audio/
│   │   │   └── pipewire.nix
│   │   ├── dev/
│   │   │   ├── tools.nix
│   │   │   ├── virtualization.nix
│   │   │   └── emacs.nix
│   │   ├── services/                      # endeavour-side
│   │   │   ├── nginx.nix
│   │   │   ├── postgres.nix
│   │   │   ├── forgejo.nix                # includes services-nginx, services-postgres
│   │   │   ├── forgejo-runner.nix
│   │   │   ├── jellyfin.nix               # includes services-nginx
│   │   │   ├── searx.nix                  # includes services-nginx
│   │   │   ├── greenlight.nix             # declares flake-file.inputs.greenlight
│   │   │   ├── panko.nix                  # declares flake-file.inputs.panko
│   │   │   ├── blocky.nix
│   │   │   ├── cloudflared.nix
│   │   │   └── lakeline-cg.nix            # declares flake-file.inputs.lakeline-cg
│   │   ├── hardware/
│   │   │   ├── lan.nix
│   │   │   ├── brother-printer.nix
│   │   │   ├── freerdp.nix
│   │   │   └── steam.nix
│   │   └── fonts.nix
│   ├── home/                              # user-agnostic home-manager modules
│   │   ├── defaults.nix
│   │   ├── niri.nix
│   │   ├── hyprland.nix
│   │   ├── tablet-mode.nix
│   │   ├── ghostty.nix
│   │   ├── wezterm.nix
│   │   ├── alacritty.nix
│   │   ├── zed-editor.nix
│   │   ├── tea.nix
│   │   ├── languages.nix
│   │   ├── brave.nix
│   │   ├── rofi.nix
│   │   ├── wlr-which-key.nix
│   │   ├── desktop-tools.nix
│   │   └── virt-manager.nix
│   ├── users/
│   │   ├── jordangarrison.nix             # includes baseline home-manager
│   │   ├── mikayla.nix                    # classes = ["nixos"] (no HM)
│   │   ├── jane.nix
│   │   └── isla.nix
│   ├── hosts/
│   │   ├── endeavour.nix
│   │   ├── opportunity.nix
│   │   ├── voyager.nix
│   │   ├── discovery.nix
│   │   ├── flomac.nix
│   │   └── normandy.nix                   # standalone home-manager via den.homes
│   └── overlays/
│       ├── stable.nix
│       ├── master.nix
│       ├── zed-extensions.nix
│       ├── llm-agents.nix
│       ├── ralph.nix
│       ├── scripts.nix
│       ├── okta-cli-client.nix
│       ├── sidecar.nix
│       └── tea.nix
├── packages/                              # unchanged: claude-switch, gi, ksn, ...
├── users/                                 # static assets only after migration
│   └── jordangarrison/
│       ├── configs/                       # hypr, noctalia, tools/doom.d, etc.
│       ├── tools/
│       └── wallpapers/
├── hosts/                                 # configuration.nix + hardware-configuration.nix per host
└── lib/
    └── mkScript.nix
```

The `users/<name>/nixos.nix`, `home.nix`, `home-linux.nix`, `home-darwin.nix` files get folded into `modules/users/<name>.nix`. Static assets (`users/jordangarrison/configs/`, `tools/`, `wallpapers/`) stay where they are; aspects reference them by relative path.

## Aspect, host, and user shapes

### Service aspect (NixOS-only)

```nix
# modules/aspects/services/forgejo.nix
{ den, ... }:
{
  flake-file.inputs = { };  # nothing extra required

  den.aspects.forgejo = {
    includes = [
      den.aspects.nginx
      den.aspects.postgres
    ];
    nixos = { config, pkgs, ... }: {
      services.forgejo = {
        enable = true;
        # ... existing config from modules/nixos/forgejo.nix
      };
    };
  };
}
```

### Aspect that pulls in an external flake input

```nix
# modules/aspects/services/greenlight.nix
{ den, inputs, ... }:
{
  flake-file.inputs.greenlight = {
    url = "github:jordangarrison/greenlight";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.greenlight = {
    includes = [ den.aspects.nginx ];
    nixos = {
      imports = [ inputs.greenlight.nixosModules.default ];
      services.greenlight = { /* ... */ };
    };
  };
}
```

### User-agnostic home module

```nix
# modules/home/niri.nix
{ pkgs, ... }:
{
  programs.niri.settings = { /* ... */ };
  wayland.windowManager.niri = { /* ... */ };
}
```

No Den specifics. No username. Just a regular home-manager module.

### User aspect with home-manager

```nix
# modules/users/jordangarrison.nix
{ den, ... }:
{
  den.aspects.jordangarrison = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
      (den.provides.user-shell "fish")
    ];
    nixos = {
      users.users.jordangarrison.extraGroups = [
        "wheel" "networkmanager" "docker" "input"
      ];
    };
    homeManager = { pkgs, ... }: {
      imports = [
        ../home/defaults.nix
        ../home/ghostty.nix
        ../home/wezterm.nix
        ../home/alacritty.nix
        ../home/zed-editor.nix
        ../home/brave.nix
        ../home/languages.nix
        ../home/rofi.nix
        ../home/desktop-tools.nix
      ];
    };
  };
}
```

The `den.provides.user-shell` battery may be used to set the login shell; the exact shell value is a translation detail captured during step 5 of the migration sequence (current zsh setup preserved).

### User aspect without home-manager

```nix
# modules/users/mikayla.nix
{ den, ... }:
{
  den.aspects.mikayla = {
    classes = [ "nixos" ];   # opt out of homeManager
    includes = [ den.provides.define-user ];
    nixos = {
      users.users.mikayla = {
        isNormalUser = true;
        # ... groups, shell, etc.
      };
    };
  };
}
```

### Host aspect with per-host home extras

```nix
# modules/hosts/endeavour.nix
{ den, inputs, ... }:
{
  flake-file.inputs.nixos-hardware = { url = "github:NixOS/nixos-hardware"; };

  den.hosts.x86_64-linux.endeavour.users = {
    jordangarrison = { };
    mikayla = { };
    jane = { };
    isla = { };
  };

  den.aspects.endeavour = {
    includes = [
      den.aspects.common
      den.aspects.gnome
      den.aspects.niri
      den.aspects.pipewire
      den.aspects.fonts
      den.aspects.dev-tools
      den.aspects.virtualization
      den.aspects.lan
      den.aspects.brother-printer
      den.aspects.freerdp
      den.aspects.nginx
      den.aspects.postgres
      den.aspects.forgejo
      den.aspects.forgejo-runner
      den.aspects.jellyfin
      den.aspects.searx
      den.aspects.greenlight
      den.aspects.panko
      den.aspects.blocky
      den.aspects.cloudflared
      den.aspects.lakeline-cg
    ];
    nixos = {
      imports = [
        ../../hosts/endeavour/configuration.nix
        ../../hosts/endeavour/hardware-configuration.nix
        inputs.nixos-hardware.nixosModules.msi-b550-a-pro
        inputs.nixos-hardware.nixosModules.common-gpu-amd
      ];
    };
    # endeavour-specific home-manager extras for any user with HM enabled
    provides.to-users.homeManager = {
      imports = [
        ../home/niri.nix
        ../home/tea.nix
      ];
    };
  };
}
```

For users with `classes = ["nixos"]` (mikayla/jane/isla), the `provides.to-users.homeManager` is a no-op. For jordangarrison, it merges with their baseline home-manager config.

### Standalone home-manager host (normandy)

```nix
# modules/hosts/normandy.nix
{ den, ... }:
{
  den.homes.x86_64-linux."jordangarrison@normandy" = {
    user = "jordangarrison";
    homeDirectory = "/home/jordangarrison";
  };

  # The jordangarrison user aspect already declares the baseline HM imports;
  # no additional host-specific extras for normandy.
}
```

### Overlay registration

```nix
# modules/overlays/stable.nix
{ inputs, ... }:
{
  flake-file.inputs.nixpkgs-stable = {
    url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  den.default.nixos.nixpkgs.overlays = [
    (final: prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (prev) system;
        config.allowUnfree = true;
      };
    })
  ];
  den.default.darwin.nixpkgs.overlays = [
    (final: prev: {
      stable = import inputs.nixpkgs-stable {
        inherit (prev) system;
        config.allowUnfree = true;
      };
    })
  ];
}
```

`den.default.<class>` applies globally — overlays self-register on every host of that class.

## What gets deleted

After migration, the following can be removed:
- `modules/nixos/*.nix` (each is now an aspect under `modules/aspects/`)
- `modules/home/*` directories (folded into `modules/home/*.nix` flat files)
- `modules/*-overlay.nix` (now `modules/overlays/*.nix`)
- The hand-maintained per-host `modules = [ ... ]` block in the old `flake.nix`
- The repeated user-enable blocks across hosts
- `users/<name>/nixos.nix`, `home.nix`, `home-linux.nix`, `home-darwin.nix` (folded into `modules/users/<name>.nix`)

What stays unchanged:
- `packages/` directory
- `hosts/<name>/configuration.nix` and `hardware-configuration.nix`
- `lib/mkScript.nix`
- `users/<name>/configs/`, `tools/`, `wallpapers/` (static assets)
- `docs/`, `shell.nix`, `install-determinant-systems-nix.sh`

## Migration sequence

Single feature branch; no incremental rollout. Order of work:

1. **Branch + scaffold** — create `modules/dendritic.nix`, `modules/defaults.nix`, empty `modules/{aspects,home,users,hosts,overlays}/` directories. Keep old `flake.nix` working alongside.
2. **Overlays** — port each overlay file. Verify a build still succeeds with the old `flake.nix`.
3. **Aspect translation** — for each `modules/nixos/*.nix`: create matching `modules/aspects/<category>/<name>.nix` declaring `den.aspects.<name>`. Translate any `nixpkgs.config` / `inputs.<x>` references. Mark dependency edges via `includes`. Each aspect that references an external flake input also declares it via `flake-file.inputs`.
4. **Home modules** — flatten `modules/home/<name>/` into `modules/home/<name>.nix` (user-agnostic).
5. **User aspects** — fold `users/<name>/{nixos,home,home-linux,home-darwin}.nix` into `modules/users/<name>.nix`. Translate the existing `users.<name>.enable` custom-option pattern into `den.hosts.*.users.<name> = {}` declarations on each relevant host.
6. **Host files** — write `modules/hosts/<host>.nix` for each of endeavour, opportunity, voyager, discovery, flomac, normandy.
7. **Switch entrypoint** — replace `flake.nix` with the auto-generated stub. Run `nix run .#write-flake` to confirm.
8. **Validate** — see Validation section.
9. **Cleanup** — delete the old files (now superseded).
10. **Merge** — single PR.

### Inputs to migrate

Every current `flake.nix` input gets declared inline by the aspect that uses it:

| Current input | Owning module after migration |
|---|---|
| `nixpkgs`, `nixpkgs-stable`, `nixpkgs-master` | `modules/dendritic.nix` (core) + `modules/overlays/{stable,master}.nix` |
| `nixos-hardware` | each host file that imports a hardware module |
| `nix-darwin` | `modules/hosts/flomac.nix` |
| `home-manager` | `modules/dendritic.nix` (core) |
| `nvf` | `modules/home/<editor>.nix` (consumer of nvf) |
| `niri`, `noctalia` | `modules/aspects/desktop/niri.nix` + `modules/home/niri.nix` |
| `aws-tools`, `aws-use-sso`, `hubctl`, `sweet-nothings`, `grove`, `warp-preview` | `modules/users/jordangarrison.nix` (or split per-aspect if introduced later) |
| `llm-agents` | `modules/overlays/llm-agents.nix` |
| `nix-zed-extensions` | `modules/overlays/zed-extensions.nix` |
| `greenlight` | `modules/aspects/services/greenlight.nix` |
| `panko` | `modules/aspects/services/panko.nix` |
| `lakeline-cg` (SSH URL — see risks) | `modules/aspects/services/lakeline-cg.nix` |

## Validation

Every host must build cleanly before merge:

```bash
nh os build .#endeavour --no-nom
nh os build .#opportunity --no-nom
nh os build .#voyager --no-nom
nh os build .#discovery --no-nom
nh darwin build .#H952L3DPHH --no-nom
nix build .#homeConfigurations."jordangarrison@normandy".activationPackage
```

After all builds succeed, on whatever host the migration was done from:
```bash
nh os test .   # (or nh darwin test .)
```

Then `nh os switch .` to confirm runtime parity (services up, desktop sessions, etc.).

Spot checks on endeavour after switch:
- `systemctl status forgejo nginx postgres jellyfin blocky` — all active
- `nix run` paths still work for `aws-use-sso`, `hubctl`, `greenlight`
- niri session launches; tea CLI authenticates against forgejo
- jordangarrison home-manager activates cleanly

## Risks and unknowns

- **Den's `provides.to-users.homeManager` semantics on a multi-user host where some users opt out of HM**: design assumes the no-HM users silently ignore the host's HM provision. Needs verification on first host build. If wrong, fallback is per-user-keyed `provides.to-users.<username>.homeManager` (Den supports nested context targeting).
- **Custom `users.<name>.enable` system option** (currently in `users/<name>/nixos.nix`): the `den.hosts.<sys>.<host>.users.<name> = {}` mechanism replaces this. The custom option goes away. Any references in other modules need to be updated.
- **`gbg-config.machine.type = "laptop"`** option used on opportunity/voyager: this is a custom option likely defined somewhere. Survey during step 3 and either keep as a host-local module setting or convert to an aspect.
- **`flake-file` regeneration** can produce a `flake.nix` diff on every input change. Acceptable cost for the locality win; revert path is to remove `flake-file` and hand-maintain inputs.
- **Niri/Hyprland `programs.niri.settings = {}` style**: current home-modules use the niri-flake home-manager module. The niri aspect on the system side (`den.aspects.niri`) needs to import `inputs.niri.nixosModules.niri`; the home aspect imports `inputs.niri.homeModules.niri`. Wire this in the relevant aspect files.

- **lakeline-cg input uses an SSH-based git URL** (`git+ssh://forgejo@forgejo.jordangarrison.dev/jordangarrison/cg.git`). `flake-file` should preserve this URL string unchanged when generating `flake.nix`; the input requires a working SSH agent and key access at lock/update time. No semantic change vs current setup.

## Out of scope

- Refactoring the `users/jordangarrison/configs/` Doom Emacs literate config or related `tools/` content.
- Touching `packages/` or `lib/` internals.
- Fine-grained aspect decomposition (per-vhost, per-keybind, etc.). Coarse first; refine on demand.
- Migrating to `npins` or any non-flake dependency tooling.
