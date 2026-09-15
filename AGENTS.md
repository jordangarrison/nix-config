# AGENTS.md

Guidance for coding agents working in Jordan Garrison's multi-platform Nix
configuration. Keep this file as a map, a set of safety invariants, and an index
to focused documentation. Derive inventories from the source instead of copying
them here.

## Non-negotiable rules

- Every `nh` build, test, or switch invocation must include `--no-nom`. The
  nix-output-monitor TUI obscures useful output in agent sessions. Other `nh`
  subcommands may not support that flag.
- For NixOS changes, run **build → test → switch**, in that order. Run `switch`
  only after the first two pass and the user explicitly confirms.
- For nix-darwin and standalone Home Manager changes, build/check first where
  supported and ask before applying with `switch`.
- Never re-enable suspend on `voyager` or change its `machine.type` from
  `"desktop"` to `"laptop"`. Suspend permanently disables the internal SD
  reader backing the family `/data` share until a cold power-off. The rationale
  and failed workarounds are documented in `hosts/voyager/configuration.nix`.
- Do not edit generated or Nix-managed symlinks in place. Change their Nix source
  and rebuild.
- Do not expose, copy into the repository, or manually print secrets. Use the
  repository's wrapped tools and declared secret paths.
- Do not commit or push unless the user asks.

## Essential commands

### NixOS

```bash
nh os build . --no-nom
nh os test . --no-nom
# Only after both pass and the user approves:
nh os switch . --no-nom
```

### nix-darwin

```bash
nh darwin build . --no-nom
# Ask before applying:
nh darwin switch . --no-nom
```

### Standalone Home Manager

```bash
# Used for WSL/Ubuntu configurations, not hosts managed above.
nh home build . --no-nom
# Ask before applying:
nh home switch . --no-nom
```

### Flakes and development

```bash
nix flake check
nix flake show
nix flake update
nix develop
```

When updating inputs, inspect `flake.lock`, then validate the affected system.
For package and option discovery, prefer the Nix MCP over guessing names or
versions.

## Repository map

`flake.nix` is the composition root. It defines NixOS, nix-darwin, and standalone
Home Manager outputs and wires overlays, hosts, users, and external flakes.

- `hosts/<name>/` — host-specific and hardware configuration.
- `users/<name>/` — account definitions and Home Manager configuration.
- `modules/nixos/` — shared NixOS modules, including infrastructure services.
- `modules/home/` — shared Home Manager modules.
- `modules/*-overlay.nix` — overlays for stable/master packages, editor
  extensions, LLM tooling, and custom packages.
- `packages/` — locally packaged scripts and utilities.
- `lib/` — shared Nix helpers such as `mkScript.nix`.
- `docs/adr/`, `docs/plans/`, `docs/lessons-learned/`, `docs/runbooks/` —
  decisions, implementation records, lessons, and operations.

Prefer inspecting `flake.nix` and directory contents over relying on a static
module, package, service, or input inventory.

## Configurations and host invariants

### NixOS

- `endeavour` — primary workstation and home-services host.
- `opportunity` — Framework 12 laptop; tablet mode is enabled.
- `voyager` — always-on MacBook Pro server. **It must never suspend; see the
  non-negotiable rule above.**
- `discovery` — AMD system with a minimal GNOME setup.

### Other platforms

- `H952L3DPHH` — work MacBook managed by nix-darwin.
- `jordangarrison@normandy` — standalone Home Manager on WSL/Ubuntu.

## Common changes

### Add packages

System-wide packages generally belong in the relevant host or NixOS module.
Jordan's user packages generally belong in `users/jordangarrison/home.nix`.
Local shell-script packages should use `lib/mkScript.nix` and be exposed through
the appropriate overlay.

Before adding a package:

1. Confirm its nixpkgs attribute and versions with the Nix MCP.
2. Choose system, user, or host scope deliberately.
3. Avoid adding another overlay when an existing one has the correct ownership.
4. Build the affected output.

### Update flake inputs

```bash
nix flake update
git diff -- flake.lock
```

Validate the affected configuration using the commands above. Updating the
private `floai` input requires GitHub SSH access; CI replaces it with
`ci/stubs/floai`.

### Cloudflare DNS

DNS for `jordangarrison.dev` uses the wrapped `flarectl`, which reads
`/var/lib/acme-secrets/cloudflare-env`. Do not export or display the token
manually. Self-hosted services conventionally use an unproxied A record to
`100.118.65.11` with TTL `1`.

```bash
flarectl dns list --zone jordangarrison.dev
flarectl dns create --zone jordangarrison.dev --name <subdomain> \
  --type A --content 100.118.65.11 --ttl 1
```

Inspect existing records before creating, updating, or deleting one. DNS
mutations require explicit user intent.

## Read when touching these areas

Read the focused guidance before changing the corresponding subsystem:

| Area | Authoritative guidance |
| --- | --- |
| Voyager power, lid, or `/data` behavior | `hosts/voyager/configuration.nix` |
| Niri | `modules/home/niri/CLAUDE.md` |
| Tablet mode, gestures, rotation, or OSK | `modules/home/tablet-mode/README.md` |
| Hyprland or monitor configuration | `users/jordangarrison/configs/hypr/CLAUDE.md` |
| Noctalia | `users/jordangarrison/configs/noctalia/README.md` |
| Doom Emacs | `users/jordangarrison/tools/doom.d/AGENTS.md` |
| nvf/Neovim | `users/jordangarrison/tools/nvim/README.md` |
| Herdr persistence, updates, or recovery | `docs/runbooks/herdr.md` and `modules/home/herdr/` |
| Agent configuration and routing | `users/jordangarrison/agents/AGENTS.md` |
| Skills | `users/jordangarrison/skills/CLAUDE.md` |

Source-local comments and module options take precedence over summaries. If a
subsystem lacks focused guidance, inspect its implementation and add concise
local documentation only when the behavior is non-obvious or safety-critical.

## Infrastructure services

Services hosted on `endeavour` are defined in `modules/nixos/` and composed in
the host configuration. Inspect the relevant module rather than using a copied
service catalog. Common operational checks are:

```bash
systemctl status <service>
journalctl -u <service> -f
```

Ask before restarting a service or applying a system configuration.

## Herdr invariants

Herdr is managed by `programs.herdr` in `modules/home/herdr/`, gated by
`userApps.herdr.enable`. Its `config.toml` is a read-only Nix symlink: change
`users/jordangarrison/home.nix` and rebuild instead of editing it through the UI.
Mutable runtime state remains under `~/.config/herdr/`.

On Nix, do not use `herdr update --handoff`; its downloader cannot write to the
Nix store. Update the `llm-agents` input, rebuild with the normal guarded flow,
then run `herdr-handoff`. See `docs/runbooks/herdr.md` for persistence caveats
and crash-loop recovery.

## Documentation policy

Keep this root file short. Add content here only when every agent must know it
before acting. Put subsystem procedures beside their implementation or in a
focused runbook, then add one path-triggered entry above. Avoid repeating source
inventories, end-user feature descriptions, or the same command policy in
multiple sections.
