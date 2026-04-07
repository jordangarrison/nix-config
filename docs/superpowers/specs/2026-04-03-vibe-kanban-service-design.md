# Vibe Kanban NixOS Service

**Date:** 2026-04-03
**Status:** Approved

## Summary

Deploy [Vibe Kanban](https://github.com/BloopAI/vibe-kanban) as a NixOS systemd service on `endeavour`, using the pre-built package from the NumTide `llm-agents.nix` flake. Expose it at `vibe-kanban.jordangarrison.dev` via nginx reverse proxy with ACME TLS.

## Motivation

Vibe Kanban provides a kanban board for planning and executing work with AI coding agents (Claude Code, Gemini CLI, Copilot). Running it as a persistent service means it's always available via a vanity URL, consistent with how Greenlight and Forgejo are deployed.

## Architecture

```
Browser → vibe-kanban.jordangarrison.dev (HTTPS/443)
       → nginx reverse proxy (ACME via Cloudflare DNS-01)
       → localhost:7780 (vibe-kanban process)
       → runs as jordangarrison, full access to ~/dev, git repos, dev tools
```

## Design Decisions

### Package source: NumTide llm-agents.nix overlay

The `llm-agents.nix` flake already packages `vibe-kanban` (v0.1.2 at time of writing). It's available as `pkgs.llm-agents.vibe-kanban` through the existing overlay in `modules/llm-agents-overlay.nix`. No custom Nix packaging required.

### Run as user, not system service

Vibe Kanban needs access to local git repos, dev tools, SSH keys, and the user's environment to function. Running as a dedicated system user would require extensive bind-mounting and permission grants that defeat the purpose. Running as `jordangarrison` gives it natural access to everything.

### Host-level config, not reusable module

Unlike Greenlight (which exports `nixosModules.default` for reuse), this is a simple host-level config file. Vibe Kanban is a third-party tool deployed on a single machine — a reusable options module would be over-engineering.

### Port 7780

Follows the established convention: 4000 range for user-built tools (Greenlight at 4444), 7000 range for off-the-shelf tools (Forgejo at 7770, Vibe Kanban at 7780).

## Components

### 1. `modules/nixos/vibe-kanban.nix`

Systemd service definition:

- **User:** `jordangarrison`
- **ExecStart:** `${pkgs.llm-agents.vibe-kanban}/bin/vibe-kanban` (verify binary name from package during implementation)
- **Environment:**
  - `PORT=7780`
  - `HOST=127.0.0.1`
  - `VK_ALLOWED_ORIGINS=https://vibe-kanban.jordangarrison.dev` (verify exact env var name from upstream source)
- **WorkingDirectory:** `/home/jordangarrison`
- **Wants:** `network-online.target`
- **After:** `network-online.target`
- **Restart:** `on-failure`
- **RestartSec:** `5`

ACME certificate:

```nix
security.acme.certs."vibe-kanban.jordangarrison.dev" = {
  group = "nginx";
};
```

Nginx virtualhost:

```nix
services.nginx.virtualHosts."vibe-kanban.jordangarrison.dev" = {
  forceSSL = true;
  useACMEHost = "vibe-kanban.jordangarrison.dev";
  locations."/" = {
    proxyPass = "http://localhost:7780";
    proxyWebsockets = true;
  };
};
```

### 2. `flake.nix` change

Add one line to the `endeavour` modules list:

```nix
./modules/nixos/vibe-kanban.nix
```

### 3. DNS record (manual)

Add a Cloudflare DNS record for `vibe-kanban.jordangarrison.dev` pointing to the endeavour machine (same method as Greenlight and Forgejo — A record or CNAME to Tailscale IP).

## Implementation notes

- **Browser auto-open:** Vibe Kanban may attempt to open a browser on startup. In a headless systemd context, ensure this doesn't block the process (may need `--no-open` flag or PATH without `xdg-open`).
- **State directory:** Vibe Kanban persists profiles, workspace state, and caches. Verify where state lands (likely `$HOME/.vibe-kanban/` or CWD) and document it.
- **WebSocket timeouts:** If idle WebSocket connections drop, increase `proxy_read_timeout` in the nginx location block.

## What's NOT included

- **No dedicated system user** — runs as user for full dev environment access
- **No secrets management** — Vibe Kanban doesn't require API tokens (agents bring their own)
- **No reusable NixOS options module** — single-host personal tool
- **No firewall changes** — nginx handles external access; service binds to localhost only
- **No Docker/OCI container** — native execution needed for dev environment access

## Verification

After `nixos-rebuild switch`:

1. `systemctl status vibe-kanban` — service is running
2. `curl http://localhost:7780` — responds locally
3. `curl https://vibe-kanban.jordangarrison.dev` — responds via nginx with valid TLS
4. Open in browser, verify it can see local git repos
