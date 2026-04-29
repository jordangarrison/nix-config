# Dendritic Nix Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate this nix-config from the monolithic `flake.nix` layout to the dendritic pattern using `vic/den`, where every aspect, host, and user is a self-registering module under a single auto-loaded tree.

**Architecture:** New tree built under `modules-new/` while old `modules/` remains untouched. New `flake.nix` (committed early) points at `modules-new/` from day one — old modules become orphan files until cleanup. After all 6 host configurations build, `modules-new/` replaces `modules/` and obsolete files are deleted.

**Tech Stack:** `vic/den` (aspect framework) + `vic/import-tree` (auto-loading) + `hercules-ci/flake-parts` (flake composition) + `vic/flake-file` (flake.nix auto-generation) + nixpkgs unstable + home-manager.

**Source spec:** `docs/superpowers/specs/2026-04-28-dendritic-nix-migration-design.md` — read it first.

---

## Conventions used in this plan

- "Verify a build" = `nh os build .#<host> --no-nom` for NixOS hosts; `nh darwin build .#<host> --no-nom` for darwin; `nix build .#homeConfigurations."jordangarrison@normandy".activationPackage` for normandy. The `--no-nom` flag is mandatory in this repo.
- "Translate" = read existing module file, write a new file in the new layout that produces equivalent runtime behavior.
- All commits use Conventional Commits per the repo's CLAUDE.md.
- `nix flake check --no-build` validates evaluation without building any derivation — useful as a syntax/eval gate before doing real builds.
- Some current modules may not be referenced by any active host (e.g., `metabase.nix`, `n8n.nix`, `podman.nix`, `acp-adapters`, `pi`). Translate them anyway — they exist for a reason and removing them is out of scope.

---

## Task 1: Branch and scaffold

**Files:**
- Create: `modules-new/` (empty tree)

- [ ] **Step 1: Create the migration branch**

```bash
git checkout -b feat/dendritic-migration
```

- [ ] **Step 2: Create scaffold directory tree**

```bash
mkdir -p modules-new/aspects/{desktop,audio,dev,services,hardware}
mkdir -p modules-new/{home,users,hosts,overlays,_meta}
```

- [ ] **Step 3: Add a placeholder so git tracks the empty dirs**

```bash
touch modules-new/_meta/.gitkeep
```

- [ ] **Step 4: Commit scaffold**

```bash
git add modules-new/
git commit -m "feat(dendritic): scaffold modules-new directory tree"
```

---

## Task 2: Bootstrap Den + flake-parts + flake-file

**Files:**
- Create: `modules-new/dendritic.nix`
- Create: `modules-new/defaults.nix`
- Modify: `flake.nix` (replace entirely with Den entrypoint)
- Modify: `flake.lock` (will regenerate when adding inputs)

The OLD `flake.nix` content is preserved in git history for reference (commit `6025c86` and earlier). After this task, `flake.nix` is the new Den entrypoint and old `modules/*.nix` files are no longer imported.

- [ ] **Step 1: Write `modules-new/dendritic.nix`**

```nix
# modules-new/dendritic.nix
{ inputs, ... }:
{
  imports = [
    inputs.flake-file.flakeModules.dendritic
    inputs.den.flakeModules.dendritic
  ];

  # Inputs declared centrally here. Aspects may add their own further down.
  flake-file.inputs = {
    den.url = "github:vic/den";
    flake-file.url = "github:vic/flake-file";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

- [ ] **Step 2: Write `modules-new/defaults.nix`**

```nix
# modules-new/defaults.nix
{ lib, den, ... }:
{
  den.default.nixos.system.stateVersion = "25.11";
  den.default.homeManager.home.stateVersion = "25.11";

  # Enable home-manager class on users by default; per-user opt-out is explicit.
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  # Enable mutual host<->user provision so host aspects forward HM config to their users.
  den.ctx.user.includes = [ den.provides.mutual-provider ];
}
```

- [ ] **Step 3: Replace `flake.nix` with Den entrypoint**

```nix
# flake.nix
# DO-NOT-EDIT. This file was auto-generated using github:vic/flake-file.
# Use `nix run .#write-flake` to regenerate it.
{
  description = "Jordan Garrison's NixOS, Darwin, and Home Manager configurations (dendritic)";

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules-new);

  inputs = {
    den.url = "github:vic/den";
    flake-file.url = "github:vic/flake-file";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    import-tree.url = "github:vic/import-tree";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

NOTE: Aspects in later tasks add their own inputs via `flake-file.inputs.<name>` declarations. The plan re-runs `nix run .#write-flake` at the cutover task to regenerate this file from the full module set.

- [ ] **Step 4: Update flake.lock**

```bash
nix flake lock
```

Expected: lock file updates with new inputs (den, flake-file, flake-parts, import-tree). May fail if `lakeline-cg`'s SSH input is in the old flake.lock — if it errors on lakeline-cg, see Task 12 (the input only gets re-added once we declare it inline).

- [ ] **Step 5: Verify evaluation parses**

```bash
nix flake check --no-build
```

Expected: success. May print warnings about no `nixosConfigurations` defined yet — that is expected at this stage because no host files exist.

- [ ] **Step 6: Commit**

```bash
git add flake.nix flake.lock modules-new/dendritic.nix modules-new/defaults.nix
git commit -m "feat(dendritic): bootstrap Den + flake-parts entrypoint"
```

---

## Task 3: Port overlays

**Files:**
- Create: `modules-new/overlays/{stable,master,zed-extensions,llm-agents,ralph,scripts,okta-cli-client,sidecar,tea}.nix`

Translation pattern: each existing `modules/<name>-overlay.nix` becomes `modules-new/overlays/<name>.nix` declaring `den.default.nixos.nixpkgs.overlays = [ ... ];` and (for cross-platform overlays) `den.default.darwin.nixpkgs.overlays = [ ... ];`. If the overlay sources from a flake input, also declare `flake-file.inputs.<input>` in that same file.

- [ ] **Step 1: Read the existing overlay files for reference**

```bash
cat modules/stable-overlay.nix modules/master-overlay.nix modules/zed-extensions-overlay.nix
cat modules/llm-agents-overlay.nix modules/ralph-overlay.nix modules/scripts-overlay.nix
cat modules/okta-cli-client-overlay.nix modules/sidecar-overlay.nix modules/tea-overlay.nix
```

- [ ] **Step 2: Worked example — write `modules-new/overlays/stable.nix`**

```nix
# modules-new/overlays/stable.nix
{ inputs, ... }:
let
  overlay = final: prev: {
    stable = import inputs.nixpkgs-stable {
      inherit (prev) system;
      config.allowUnfree = true;
    };
  };
in
{
  den.default.nixos.nixpkgs.overlays = [ overlay ];
  den.default.darwin.nixpkgs.overlays = [ overlay ];
}
```

- [ ] **Step 3: Write the remaining 8 overlays following the same pattern**

For each `modules/<name>-overlay.nix`, create `modules-new/overlays/<name>.nix`. Translation rules:

- Top-level module wrapper changes from `{ pkgs, ... }: { nixpkgs.overlays = [ ... ]; }` to `{ inputs, ... }: { den.default.nixos.nixpkgs.overlays = [ ... ]; den.default.darwin.nixpkgs.overlays = [ ... ]; }`.
- If the original overlay closes over a flake input, add `flake-file.inputs.<name> = { url = "..."; };` at the top of the file.
- The overlay function body itself (the `final: prev: { ... }` lambda) stays unchanged.

The full list:

| New file | Original | Special notes |
|---|---|---|
| `modules-new/overlays/stable.nix` | `modules/stable-overlay.nix` | (worked example above) |
| `modules-new/overlays/master.nix` | `modules/master-overlay.nix` | uses `inputs.nixpkgs-master` |
| `modules-new/overlays/zed-extensions.nix` | `modules/zed-extensions-overlay.nix` | declares `flake-file.inputs.nix-zed-extensions` |
| `modules-new/overlays/llm-agents.nix` | `modules/llm-agents-overlay.nix` | declares `flake-file.inputs.llm-agents` |
| `modules-new/overlays/ralph.nix` | `modules/ralph-overlay.nix` | reads `packages/ralph` |
| `modules-new/overlays/scripts.nix` | `modules/scripts-overlay.nix` | reads `packages/*` (gi, ksn, myip, td, tmux-cht, sidecar, claude-switch, flarectl) |
| `modules-new/overlays/okta-cli-client.nix` | `modules/okta-cli-client-overlay.nix` | reads `packages/okta-cli-client` |
| `modules-new/overlays/sidecar.nix` | `modules/sidecar-overlay.nix` | reads `packages/sidecar` |
| `modules-new/overlays/tea.nix` | `modules/tea-overlay.nix` | (custom tea wrapper) |

- [ ] **Step 4: Verify**

```bash
nix flake check --no-build
```

Expected: success. Check the output mentions the new inputs.

- [ ] **Step 5: Commit**

```bash
git add modules-new/overlays/
git commit -m "feat(dendritic): port overlays as den.default.nixpkgs.overlays"
```

---

## Task 4: Port base aspects (common, fonts, audio, hardware, dev)

**Files:**
- Create: `modules-new/aspects/common.nix`
- Create: `modules-new/aspects/fonts.nix`
- Create: `modules-new/aspects/audio/pipewire.nix`
- Create: `modules-new/aspects/hardware/{lan,brother-printer,freerdp,steam}.nix`
- Create: `modules-new/aspects/dev/{tools,virtualization,emacs,podman}.nix`

Translation pattern: existing `modules/nixos/<name>.nix` typically looks like `{ pkgs, ... }: { /* config */ }`. New aspect file becomes `{ den, ... }: { den.aspects.<name>.nixos = { pkgs, ... }: { /* config */ }; }`. The original module body becomes the value of `nixos`.

- [ ] **Step 1: Worked example — `modules-new/aspects/common.nix`**

Read `modules/nixos/common.nix` and translate:

```nix
# modules-new/aspects/common.nix
{ den, ... }:
{
  den.aspects.common.nixos = { config, pkgs, lib, ... }: {
    # paste the entire body of modules/nixos/common.nix here, unchanged
    # (networking, locale, Tailscale, 1Password, environment.systemPackages, etc.)
  };
}
```

- [ ] **Step 2: Translate the remaining base aspects**

For each, the pattern is identical: wrap the existing module body in `den.aspects.<name>.nixos = original_body`. Mapping:

| New aspect file | Original | Aspect name |
|---|---|---|
| `modules-new/aspects/fonts.nix` | `modules/nixos/fonts.nix` | `fonts` |
| `modules-new/aspects/audio/pipewire.nix` | `modules/nixos/audio/pipewire.nix` | `pipewire` |
| `modules-new/aspects/hardware/lan.nix` | `modules/nixos/lan.nix` | `lan` |
| `modules-new/aspects/hardware/brother-printer.nix` | `modules/nixos/brother-printer.nix` | `brother-printer` |
| `modules-new/aspects/hardware/freerdp.nix` | `modules/nixos/freerdp.nix` | `freerdp` |
| `modules-new/aspects/hardware/steam.nix` | `modules/nixos/steam.nix` (if used by any host) | `steam` |
| `modules-new/aspects/dev/tools.nix` | `modules/nixos/development.nix` | `dev-tools` |
| `modules-new/aspects/dev/virtualization.nix` | `modules/nixos/virtualization.nix` | `virtualization` |
| `modules-new/aspects/dev/emacs.nix` | `modules/nixos/emacs.nix` | `emacs` (cross-class: also exposes `darwin = ...;` since flomac uses it) |
| `modules-new/aspects/dev/podman.nix` | `modules/nixos/podman.nix` | `podman` |

For `emacs.nix`, the original is shared between NixOS and Darwin. The new aspect declares both:

```nix
# modules-new/aspects/dev/emacs.nix
{ den, ... }:
let
  emacsConfig = { config, pkgs, lib, ... }: {
    # paste body of modules/nixos/emacs.nix
  };
in
{
  den.aspects.emacs = {
    nixos = emacsConfig;
    darwin = emacsConfig;
  };
}
```

- [ ] **Step 3: Verify**

```bash
nix flake check --no-build
```

Expected: success.

- [ ] **Step 4: Commit**

```bash
git add modules-new/aspects/
git commit -m "feat(dendritic): port base aspects (common, fonts, audio, hardware, dev)"
```

---

## Task 5: Port desktop aspects

**Files:**
- Create: `modules-new/aspects/desktop/{gnome,niri,hyprland,tablet-mode}.nix`

`niri` and `hyprland` need their flake inputs declared inline (`niri-flake`, `hyprland`).

- [ ] **Step 1: Worked example — `modules-new/aspects/desktop/niri.nix`**

```nix
# modules-new/aspects/desktop/niri.nix
{ den, inputs, ... }:
{
  flake-file.inputs.niri.url = "github:sodiboo/niri-flake";
  flake-file.inputs.noctalia = {
    url = "github:noctalia-dev/noctalia-shell";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.niri.nixos = { config, pkgs, lib, ... }: {
    imports = [ inputs.niri.nixosModules.niri ];
    # paste body of modules/nixos/niri-desktop.nix
  };
}
```

- [ ] **Step 2: Translate `gnome` and `hyprland`**

```nix
# modules-new/aspects/desktop/gnome.nix
{ den, ... }:
{
  den.aspects.gnome.nixos = { config, pkgs, lib, ... }: {
    # paste body of modules/nixos/gnome-desktop.nix
  };
}
```

```nix
# modules-new/aspects/desktop/hyprland.nix
{ den, inputs, ... }:
{
  # If hyprland-desktop.nix references inputs.hyprland, declare it here.
  # Check the original file first; current modules/nixos/hyprland-desktop.nix
  # uses `programs.hyprland.enable = true;` from nixpkgs, so no input needed.

  den.aspects.hyprland.nixos = { config, pkgs, lib, ... }: {
    # paste body of modules/nixos/hyprland-desktop.nix
  };
}
```

- [ ] **Step 3: Translate `tablet-mode` (depends on niri)**

```nix
# modules-new/aspects/desktop/tablet-mode.nix
{ den, ... }:
{
  den.aspects.tablet-mode = {
    includes = [ den.aspects.niri ];
    nixos = { config, pkgs, lib, ... }: {
      # paste body of modules/nixos/tablet-mode.nix
    };
  };
}
```

- [ ] **Step 4: Verify**

```bash
nix flake check --no-build
```

- [ ] **Step 5: Commit**

```bash
git add modules-new/aspects/desktop/
git commit -m "feat(dendritic): port desktop aspects (gnome, niri, hyprland, tablet-mode)"
```

---

## Task 6: Port foundation service aspects (nginx, postgres, blocky, cloudflared)

**Files:**
- Create: `modules-new/aspects/services/{nginx,postgres,blocky,cloudflared}.nix`

These have no inter-aspect dependencies and are foundational for other services.

- [ ] **Step 1: Worked example — `modules-new/aspects/services/nginx.nix`**

```nix
# modules-new/aspects/services/nginx.nix
{ den, ... }:
{
  den.aspects.nginx.nixos = { config, pkgs, lib, ... }: {
    # paste body of modules/nixos/nginx.nix unchanged
  };
}
```

- [ ] **Step 2: Translate the remaining 3**

| New file | Original | Aspect name |
|---|---|---|
| `modules-new/aspects/services/postgres.nix` | `modules/nixos/postgres.nix` | `postgres` |
| `modules-new/aspects/services/blocky.nix` | `modules/nixos/blocky.nix` | `blocky` |
| `modules-new/aspects/services/cloudflared.nix` | `modules/nixos/cloudflared.nix` | `cloudflared` |

Apply the same wrapper pattern as nginx.

- [ ] **Step 3: Verify**

```bash
nix flake check --no-build
```

- [ ] **Step 4: Commit**

```bash
git add modules-new/aspects/services/
git commit -m "feat(dendritic): port foundation service aspects (nginx, postgres, blocky, cloudflared)"
```

---

## Task 7: Port dependent service aspects

**Files:**
- Create: `modules-new/aspects/services/{forgejo,forgejo-runner,jellyfin,searx,greenlight,panko,lakeline-cg,metabase,n8n}.nix`

Several declare external flake inputs and `includes` edges to nginx/postgres.

- [ ] **Step 1: Worked example — `modules-new/aspects/services/forgejo.nix`**

```nix
# modules-new/aspects/services/forgejo.nix
{ den, ... }:
{
  den.aspects.forgejo = {
    includes = [
      den.aspects.nginx
      den.aspects.postgres
    ];
    nixos = { config, pkgs, lib, ... }: {
      # paste body of modules/nixos/forgejo.nix
    };
  };
}
```

- [ ] **Step 2: Worked example — service with external flake input (`greenlight.nix`)**

```nix
# modules-new/aspects/services/greenlight.nix
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
      # paste body of modules/nixos/greenlight.nix
    };
  };
}
```

- [ ] **Step 3: Worked example — `lakeline-cg.nix` (SSH-based input)**

```nix
# modules-new/aspects/services/lakeline-cg.nix
{ den, inputs, ... }:
{
  flake-file.inputs.lakeline-cg = {
    url = "git+ssh://forgejo@forgejo.jordangarrison.dev/jordangarrison/cg.git";
  };

  den.aspects.lakeline-cg = {
    includes = [ den.aspects.nginx ];
    nixos = {
      imports = [ inputs.lakeline-cg.nixosModules.default ];
      # paste body of modules/nixos/lakeline-cg.nix
    };
  };
}
```

- [ ] **Step 4: Translate the remaining services**

| New file | Original | `includes` | External input |
|---|---|---|---|
| `modules-new/aspects/services/forgejo-runner.nix` | `modules/nixos/forgejo-runner.nix` | `forgejo` | none |
| `modules-new/aspects/services/jellyfin.nix` | `modules/nixos/jellyfin.nix` | `nginx` | none |
| `modules-new/aspects/services/searx.nix` | `modules/nixos/searx.nix` | `nginx` | none |
| `modules-new/aspects/services/panko.nix` | `modules/nixos/panko.nix` | `nginx` | `flake-file.inputs.panko = { url = "github:jordangarrison/panko"; inputs.nixpkgs.follows = "nixpkgs"; };` + `imports = [ inputs.panko.nixosModules.default ];` |
| `modules-new/aspects/services/metabase.nix` | `modules/nixos/metabase.nix` | (check original) | none |
| `modules-new/aspects/services/n8n.nix` | `modules/nixos/n8n.nix` | (check original) | none |

- [ ] **Step 5: Verify**

```bash
nix flake check --no-build
```

If `lakeline-cg` lock fails due to SSH, ensure ssh-agent has the right key loaded:

```bash
ssh-add -l    # should list a key matching ~/.ssh/id_ed25519
```

- [ ] **Step 6: Commit**

```bash
git add modules-new/aspects/services/
git commit -m "feat(dendritic): port dependent service aspects with includes graph"
```

---

## Task 8: Port home modules (user-agnostic)

**Files:**
- Create: `modules-new/home/{defaults,niri,hyprland,tablet-mode,ghostty,wezterm,alacritty,zed-editor,tea,languages,brave,rofi,wlr-which-key,desktop-tools,virt-manager,acp-adapters,pi}.nix`

Home modules are NOT Den aspects — they're plain home-manager modules that get imported by user aspects or by `provides.to-users.homeManager` in host aspects. The flattening rule: each `modules/home/<name>/` subdirectory containing a `default.nix` becomes a single `modules-new/home/<name>.nix`. If the directory has multiple files, fold them via `imports = [ ./bits.nix ];` inside the new file or inline them.

Important: home modules must NOT reference any specific username. Replace any hardcoded `home.users.<name>.X` with the bare `X` form (since they're applied per-user by Den).

- [ ] **Step 1: Worked example — `modules-new/home/niri.nix`**

```bash
cat modules/home/niri/default.nix
ls modules/home/niri/
```

```nix
# modules-new/home/niri.nix
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ inputs.niri.homeModules.niri ];
  # paste contents of modules/home/niri/default.nix here, with any
  # `home-manager.users.<name>.X` flattened to bare `X`.

  programs.niri.settings = { /* ... */ };
}
```

If the `niri/` directory has additional files (CLAUDE.md, README, sub-configs), only the `.nix` files matter — keep their contents merged into the single output file.

- [ ] **Step 2: Translate the remaining home modules**

| New file | Original directory or file |
|---|---|
| `modules-new/home/defaults.nix` | `modules/home/defaults.nix` |
| `modules-new/home/hyprland.nix` | `modules/home/hyprland/` |
| `modules-new/home/tablet-mode.nix` | `modules/home/tablet-mode/` |
| `modules-new/home/ghostty.nix` | `modules/home/ghostty/` |
| `modules-new/home/wezterm.nix` | `modules/home/wezterm/` |
| `modules-new/home/alacritty.nix` | `modules/home/alacritty/` |
| `modules-new/home/zed-editor.nix` | `modules/home/zed-editor/` (declares `flake-file.inputs.nix-zed-extensions` if not already in overlays) |
| `modules-new/home/tea.nix` | `modules/home/tea/` |
| `modules-new/home/languages.nix` | `modules/home/languages/` |
| `modules-new/home/brave.nix` | `modules/home/brave/` |
| `modules-new/home/rofi.nix` | `modules/home/rofi/` |
| `modules-new/home/wlr-which-key.nix` | `modules/home/wlr-which-key/` |
| `modules-new/home/desktop-tools.nix` | `modules/home/desktop-tools/` |
| `modules-new/home/virt-manager.nix` | `modules/home/virt-manager/` |
| `modules-new/home/acp-adapters.nix` | `modules/home/acp-adapters/` |
| `modules-new/home/pi.nix` | `modules/home/pi/` |

For `tablet-mode.nix`: the original references device paths (`/dev/input/by-path/...`) — keep these unchanged.

For `tea.nix`: the original takes a per-host `programs.tea.logins.<host>` config from inside `flake.nix`. Move that login config into `modules-new/aspects/services/forgejo.nix` (host-specific home extras provided to its users) — see Task 11 for endeavour wiring.

- [ ] **Step 3: Verify**

```bash
nix flake check --no-build
```

- [ ] **Step 4: Commit**

```bash
git add modules-new/home/
git commit -m "feat(dendritic): port home-manager modules as user-agnostic"
```

---

## Task 9: Port user aspects

**Files:**
- Create: `modules-new/users/{jordangarrison,mikayla,jane,isla}.nix`

Each user aspect declares the user's system account + (for jordangarrison) baseline home-manager imports. mikayla/jane/isla opt out of HM via `classes = [ "nixos" ]`.

- [ ] **Step 1: Worked example — `modules-new/users/jordangarrison.nix`**

Read `users/jordangarrison/{nixos,home,home-linux,home-darwin}.nix` first to understand all current bindings.

```nix
# modules-new/users/jordangarrison.nix
{ den, inputs, ... }:
let
  homeBase = { config, pkgs, lib, ... }: {
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
    # Inline the cross-platform body of users/jordangarrison/home.nix here
    # (programs, packages, dotfiles referencing ../../users/jordangarrison/configs/, etc.)
  };
in
{
  flake-file.inputs.aws-tools = {
    url = "github:jordangarrison/aws-tools";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  flake-file.inputs.aws-use-sso = {
    url = "github:jordangarrison/aws-use-sso";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  flake-file.inputs.hubctl.url = "github:jordangarrison/hubctl";
  flake-file.inputs.sweet-nothings = {
    url = "github:jordangarrison/sweet-nothings";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  flake-file.inputs.grove = {
    url = "github:MichaelVessia/grove";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  flake-file.inputs.warp-preview = {
    url = "github:jordangarrison/warp-preview-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  flake-file.inputs.nvf = {
    url = "github:NotAShelf/nvf";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.jordangarrison = {
    includes = [
      den.provides.define-user
      den.provides.primary-user
    ];
    nixos = { config, pkgs, lib, ... }: {
      # contents of users/jordangarrison/nixos.nix, but drop the custom
      # `users.<name>.enable` option machinery — den.hosts.*.users.* replaces it
      users.users.jordangarrison = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" "docker" "input" ];
        # ... shell, hashedPassword, openssh.authorizedKeys, etc.
      };
    };
    homeManager = { config, pkgs, lib, ... }: {
      imports = [
        homeBase
        # Platform-specific bits via lib.mkIf
        (lib.mkIf pkgs.stdenv.isLinux {
          imports = [ ../home/virt-manager.nix ];
          # contents of users/jordangarrison/home-linux.nix
        })
        (lib.mkIf pkgs.stdenv.isDarwin {
          # contents of users/jordangarrison/home-darwin.nix
        })
      ];
    };
  };
}
```

- [ ] **Step 2: Worked example — `modules-new/users/mikayla.nix` (no HM)**

```nix
# modules-new/users/mikayla.nix
{ den, ... }:
{
  den.aspects.mikayla = {
    classes = [ "nixos" ];   # opt out of homeManager class
    includes = [ den.provides.define-user ];
    nixos = { config, pkgs, lib, ... }: {
      users.users.mikayla = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" ];
        # paste from users/mikayla/nixos.nix, dropping the custom enable-option machinery
      };
    };
  };
}
```

- [ ] **Step 3: Translate jane and isla following the mikayla pattern**

| New file | Original | Notes |
|---|---|---|
| `modules-new/users/jane.nix` | `users/jane/nixos.nix` | mirror mikayla's structure |
| `modules-new/users/isla.nix` | `users/isla/nixos.nix` | mirror mikayla's structure |

- [ ] **Step 4: Verify**

```bash
nix flake check --no-build
```

- [ ] **Step 5: Commit**

```bash
git add modules-new/users/
git commit -m "feat(dendritic): port user aspects (jordangarrison + family)"
```

---

## Task 10: Port voyager (simplest NixOS host) and verify build

**Files:**
- Create: `modules-new/hosts/voyager.nix`

Voyager is the smallest active NixOS host — no self-hosted services, no tablet-mode, GNOME only. Build it first to validate the bootstrap before touching the more complex hosts.

- [ ] **Step 1: Read current voyager block**

```bash
sed -n '270,322p' flake.nix    # NOTE: file path before this task replaced flake.nix; use git show 6025c86:flake.nix instead
git show 6025c86:flake.nix | sed -n '270,322p'
```

- [ ] **Step 2: Write `modules-new/hosts/voyager.nix`**

```nix
# modules-new/hosts/voyager.nix
{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.voyager.users = {
    jordangarrison = { };
    mikayla = { };
    jane = { };
    isla = { };
  };

  den.aspects.voyager = {
    includes = [
      den.aspects.common
      den.aspects.gnome
      den.aspects.pipewire
      den.aspects.fonts
      den.aspects.dev-tools
      den.aspects.lan
      den.aspects.brother-printer
    ];
    nixos = { config, pkgs, lib, ... }: {
      imports = [
        ../../hosts/voyager/configuration.nix
        ../../hosts/voyager/hardware-configuration.nix
        inputs.nixos-hardware.nixosModules.apple-macbook-pro-12-1
      ];
      # voyager has username override on jordangarrison: it uses "jordan" rather than "jordangarrison"
      # If jordangarrison's user aspect hardcodes username, override here:
      users.users.jordangarrison = {
        # username override handled by:
        # users.users.jordan from upstream user aspect renamed
      };
      # Translation note: voyager's old block had `users.jordangarrison = { username = "jordan"; ... };`
      # via the custom `users.<name>.enable` option. After dropping that machinery, set the username
      # directly via configuration.nix or via a host-local override here.
    };

    # Voyager uses GNOME-only, no per-host home extras. provides.to-users.homeManager
    # not declared.
  };
}
```

NOTE on voyager username: the original config remapped jordangarrison's home directory to `/home/jordan` and username to `jordan`. With Den, the cleanest path is to keep `jordangarrison` as the canonical username and update `hosts/voyager/configuration.nix` to map `/home/jordangarrison`. If preserving the `jordan` username is required, the host file overrides `users.users.jordan` directly and ensures the user aspect's HM config still applies (Den's mutual-provider should handle this if the aspect names match). Verify after building; if HM doesn't apply, the fallback is to add a separate `voyager-jordan` user aspect.

- [ ] **Step 3: Build voyager**

```bash
nh os build .#voyager --no-nom
```

Expected: success. If failure:
- Read the first error carefully — `nh` truncates by default; if needed: `nix build .#nixosConfigurations.voyager.config.system.build.toplevel --show-trace 2>&1 | head -100`
- Most common failures at this stage: missing aspect (typo in `den.aspects.<name>` reference) or unresolved option (`users.<name>.enable` references not removed).

- [ ] **Step 4: Commit**

```bash
git add modules-new/hosts/voyager.nix
git commit -m "feat(dendritic): port voyager host config and validate first build"
```

---

## Task 11: Port discovery, opportunity, normandy

**Files:**
- Create: `modules-new/hosts/{discovery,opportunity,normandy}.nix`

- [ ] **Step 1: Write `modules-new/hosts/discovery.nix`**

Pattern: minimal NixOS host, AMD CPU. Mirror voyager's structure, swap the hardware module:

```nix
# modules-new/hosts/discovery.nix
{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.discovery.users = {
    jordangarrison = { };
    mikayla = { };
    jane = { };
    isla = { };
  };

  den.aspects.discovery = {
    includes = [
      den.aspects.common
      den.aspects.gnome
      den.aspects.pipewire
      den.aspects.fonts
      den.aspects.lan
      den.aspects.brother-printer
    ];
    nixos = { ... }: {
      imports = [
        ../../hosts/discovery/configuration.nix
        ../../hosts/discovery/hardware-configuration.nix
        inputs.nixos-hardware.nixosModules.common-cpu-amd
        inputs.nixos-hardware.nixosModules.common-pc-ssd
      ];
    };
  };
}
```

- [ ] **Step 2: Build discovery**

```bash
nh os build .#discovery --no-nom
```

- [ ] **Step 3: Write `modules-new/hosts/opportunity.nix` (Framework 12 + tablet-mode)**

```nix
# modules-new/hosts/opportunity.nix
{ den, inputs, ... }:
{
  den.hosts.x86_64-linux.opportunity.users = {
    jordangarrison = { };
    mikayla = { };
    jane = { };
    isla = { };
  };

  den.aspects.opportunity = {
    includes = [
      den.aspects.common
      den.aspects.gnome
      den.aspects.niri
      den.aspects.tablet-mode
      den.aspects.pipewire
      den.aspects.fonts
      den.aspects.dev-tools
      den.aspects.virtualization
      den.aspects.lan
      den.aspects.brother-printer
    ];
    nixos = { config, lib, ... }: {
      imports = [
        ../../hosts/opportunity/configuration.nix
        ../../hosts/opportunity/hardware-configuration.nix
        inputs.nixos-hardware.nixosModules.framework-12-13th-gen-intel
      ];
      # the original flake had `gbg-config.machine.type = "laptop";` — preserve here
      gbg-config.machine.type = "laptop";
      tablet-mode.enable = true;
      # jordangarrison's swapSuperAlt setting from the old flake — apply directly
      # if the user-enable machinery is gone, write the equivalent option directly
      virtualisation.virt-manager = {
        enable = true;
        users = [ "jordangarrison" ];
      };
    };

    # opportunity gives jordangarrison niri + tablet-mode home extras
    provides.to-users.homeManager = { config, pkgs, lib, ... }: {
      imports = [
        ../home/niri.nix
        ../home/tablet-mode.nix
      ];
    };
  };
}
```

- [ ] **Step 4: Build opportunity**

```bash
nh os build .#opportunity --no-nom
```

- [ ] **Step 5: Write `modules-new/hosts/normandy.nix` (standalone HM)**

```nix
# modules-new/hosts/normandy.nix
{ den, ... }:
{
  # Standalone home-manager configuration for WSL/Ubuntu
  den.homes.x86_64-linux."jordangarrison@normandy" = {
    user = "jordangarrison";
    homeDirectory = "/home/jordangarrison";
  };

  # No additional aspects required: the jordangarrison aspect provides the baseline HM.
  # If a normandy-specific extra is needed later, attach it via:
  #   den.aspects."jordangarrison@normandy".homeManager = { ... };
}
```

- [ ] **Step 6: Build normandy**

```bash
nix build .#homeConfigurations."jordangarrison@normandy".activationPackage
```

NOTE: if Den exposes `homeConfigurations` under a different attribute (e.g., `den.homes` lifts to `homeConfigurations` with the same key), confirm the exact path:

```bash
nix flake show --json 2>/dev/null | jq -r '.homeConfigurations | keys[]'
```

If the key is `jordangarrison@normandy`, the build above is correct. If Den names it differently, use that name.

- [ ] **Step 7: Commit**

```bash
git add modules-new/hosts/discovery.nix modules-new/hosts/opportunity.nix modules-new/hosts/normandy.nix
git commit -m "feat(dendritic): port discovery, opportunity, normandy host configs"
```

---

## Task 12: Port endeavour (most complex) and flomac (darwin)

**Files:**
- Create: `modules-new/hosts/endeavour.nix`
- Create: `modules-new/hosts/flomac.nix`

- [ ] **Step 1: Write `modules-new/hosts/endeavour.nix`**

Endeavour is the home-server desktop with the most aspects. Read the original `endeavour` block from `git show 6025c86:flake.nix | sed -n '93,196p'` and translate every module reference to a `den.aspects.<name>` include.

```nix
# modules-new/hosts/endeavour.nix
{ den, inputs, ... }:
{
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
    nixos = { config, pkgs, lib, ... }: {
      imports = [
        ../../hosts/endeavour/configuration.nix
        ../../hosts/endeavour/hardware-configuration.nix
        inputs.nixos-hardware.nixosModules.msi-b550-a-pro
        inputs.nixos-hardware.nixosModules.common-gpu-amd
      ];
      virtualisation.virt-manager = {
        enable = true;
        users = [ "jordangarrison" ];
      };
      services.freerdp.enable = true;
      services.dns-blocking.enable = true;
    };

    # endeavour gives jordangarrison niri + tea (forgejo CLI login)
    provides.to-users.homeManager = { config, pkgs, lib, ... }: {
      imports = [
        ../home/niri.nix
        ../home/tea.nix
      ];
      # The forgejo login config moves here from the old flake.nix:
      programs.tea = {
        enable = true;
        logins.endeavour = {
          url = "https://forgejo.jordangarrison.dev";
          user = "jordangarrison";
          default = true;
          tokenFile = "/home/jordangarrison/.config/tea/endeavour-token";
          sshHost = "forgejo.jordangarrison.dev";
          sshKey = "~/.ssh/id_ed25519";
          sshAgent = true;
        };
      };
    };
  };
}
```

- [ ] **Step 2: Build endeavour**

```bash
nh os build .#endeavour --no-nom
```

If failure: most likely cause is a missing aspect in the include list, an unresolved `users.<name>.enable` option, or a service-specific config that referenced an old option path. Fix in the relevant aspect/host file and retry.

- [ ] **Step 3: Write `modules-new/hosts/flomac.nix` (darwin)**

```nix
# modules-new/hosts/flomac.nix
{ den, ... }:
{
  den.hosts.aarch64-darwin.H952L3DPHH.users."jordan.garrison" = { };

  den.aspects.flomac = {
    includes = [
      den.aspects.fonts
      den.aspects.emacs
    ];
    darwin = { config, pkgs, lib, ... }: {
      imports = [ ../../hosts/flomac/configuration.nix ];
      nix.enable = false;
      nixpkgs.config.allowUnfree = true;
    };
  };
}
```

NOTE: flomac uses username `jordan.garrison` (with a dot), not `jordangarrison`. The user aspect for `jordan.garrison` may need to be created if not handled by the existing jordangarrison aspect. Likely fix: add a thin alias aspect at `modules-new/users/jordan.garrison.nix` that delegates to jordangarrison's HM imports while declaring the dotted system username — or rename the home directory in `hosts/flomac/configuration.nix` and use a single `jordangarrison` aspect everywhere. Pick whichever preserves current macOS behavior.

- [ ] **Step 4: Build flomac**

```bash
nh darwin build .#H952L3DPHH --no-nom
```

(This requires running on the darwin host, or with `--system aarch64-darwin` if cross-eval is supported. If running from Linux, the build may fail with a system mismatch — that's acceptable for now; final validation runs on the darwin host.)

- [ ] **Step 5: Commit**

```bash
git add modules-new/hosts/endeavour.nix modules-new/hosts/flomac.nix
git commit -m "feat(dendritic): port endeavour and flomac host configs"
```

---

## Task 13: Regenerate flake.nix and validate all hosts

After all aspect inputs are declared inline, regenerate `flake.nix` from the full module graph using `flake-file`.

- [ ] **Step 1: Regenerate flake.nix**

```bash
nix run .#write-flake
```

Expected: `flake.nix` is rewritten with the union of all `flake-file.inputs` declarations across modules.

- [ ] **Step 2: Diff the regenerated flake.nix against what's there**

```bash
git diff flake.nix
```

Expected diff: addition of inputs declared in aspect files (greenlight, panko, lakeline-cg, niri, noctalia, nvf, aws-tools, aws-use-sso, hubctl, sweet-nothings, grove, warp-preview, nix-zed-extensions, llm-agents). All inputs follow nixpkgs where applicable.

- [ ] **Step 3: Update flake.lock with new declarations**

```bash
nix flake lock
```

- [ ] **Step 4: Build all 6 host configurations**

```bash
nh os build .#endeavour --no-nom && \
nh os build .#opportunity --no-nom && \
nh os build .#voyager --no-nom && \
nh os build .#discovery --no-nom && \
nh darwin build .#H952L3DPHH --no-nom && \
nix build .#homeConfigurations."jordangarrison@normandy".activationPackage
```

If running from a Linux host, the darwin build may fail on system mismatch — that's acceptable; mark it for verification on flomac itself before merge.

Each build that passes is a checkpoint. If a build fails:
- Find the offending aspect or host file
- Fix it
- Re-run that single build
- Once it passes, continue with the next host

- [ ] **Step 5: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(dendritic): regenerate flake.nix and validate all hosts build"
```

---

## Task 14: Cleanup - delete obsolete files and rename modules-new → modules

Once every host builds, the old layout is dead weight.

- [ ] **Step 1: Delete obsolete top-level files and directories**

```bash
rm -rf modules/
rm -f users/jordangarrison/nixos.nix
rm -f users/jordangarrison/home.nix
rm -f users/jordangarrison/home-linux.nix
rm -f users/jordangarrison/home-darwin.nix
rm -f users/mikayla/nixos.nix
rm -f users/jane/nixos.nix
rm -f users/isla/nixos.nix
```

NOTE: `users/jordangarrison/{configs,tools,wallpapers}` directories STAY — they hold static assets referenced by aspect files via relative paths. If `users/mikayla/`, `users/jane/`, `users/isla/` directories are now empty, remove them:

```bash
rmdir users/mikayla users/jane users/isla 2>/dev/null || true
```

- [ ] **Step 2: Rename modules-new → modules**

```bash
mv modules-new modules
```

- [ ] **Step 3: Update flake.nix path reference**

```nix
# flake.nix — change ./modules-new to ./modules in outputs
outputs = inputs:
  inputs.flake-parts.lib.mkFlake { inherit inputs; }
    (inputs.import-tree ./modules);
```

Then regenerate to keep everything in sync:

```bash
nix run .#write-flake
```

- [ ] **Step 4: Update relative-path references inside modules/**

The modules now live one directory level differently relative to `users/jordangarrison/configs/`, etc. Search for any `../../../` paths that may have shifted:

```bash
grep -rn 'users/jordangarrison/configs' modules/
grep -rn '\.\./\.\./\.\./' modules/
```

Adjust path depth as needed. (Renaming `modules-new` → `modules` doesn't change the depth, but if any `../../modules-new/` references slipped in, fix them.)

- [ ] **Step 5: Re-build all hosts to confirm cleanup didn't break anything**

```bash
nh os build .#endeavour --no-nom && \
nh os build .#opportunity --no-nom && \
nh os build .#voyager --no-nom && \
nh os build .#discovery --no-nom
```

- [ ] **Step 6: Commit cleanup**

```bash
git add -A
git commit -m "refactor(dendritic): remove obsolete modules and rename modules-new -> modules"
```

---

## Task 15: Runtime validation and final commit

Building successfully proves the configurations evaluate. Switching to the new generation proves they actually run.

- [ ] **Step 1: Test the new configuration on the current host**

If on a NixOS host:

```bash
nh os test .   # builds and activates without making the bootloader change
```

This activates the new generation in-place. If something breaks (services don't start, desktop session won't launch), revert with `sudo nixos-rebuild switch --rollback`.

- [ ] **Step 2: Spot-check key services (run on endeavour after switching)**

```bash
systemctl status forgejo nginx postgresql jellyfin blocky --no-pager
systemctl --user status lisgd iio-niri 2>/dev/null   # tablet-mode hosts only
```

Expected: all listed services Active.

- [ ] **Step 3: Spot-check user environment**

```bash
which gi ksn myip td tmux-cht claude-switch flarectl   # custom packages from scripts overlay
which aws-use-sso hubctl                                # custom flake inputs
tea login list                                          # forgejo CLI authenticated
```

- [ ] **Step 4: Switch the bootloader entry**

```bash
nh os switch .
```

- [ ] **Step 5: Reboot and confirm clean boot**

```bash
sudo systemctl reboot
```

After reboot, log in, confirm desktop session launches, services come up.

- [ ] **Step 6: If any post-switch fixes were needed, commit them**

```bash
git add -A
git commit -m "fix(dendritic): post-switch runtime fixes"
```

- [ ] **Step 7: Push the branch**

```bash
git push -u origin feat/dendritic-migration
```

- [ ] **Step 8: Open a PR**

Use the `@.github/PULL_REQUEST_TEMPLATE.md` if present. Title: `feat(dendritic): migrate nix-config to vic/den dendritic pattern`. Body summarizes the spec, the migration sequence, and the validation evidence (each host builds + endeavour switched cleanly).
