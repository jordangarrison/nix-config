# Vibe Kanban NixOS Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Vibe Kanban as a persistent NixOS systemd service on endeavour with nginx reverse proxy at `vibe-kanban.jordangarrison.dev`.

**Architecture:** A NixOS module wraps the pre-built `pkgs.llm-agents.vibe-kanban` package from the NumTide llm-agents overlay into a systemd service running as the `jordangarrison` user. Nginx terminates TLS via Cloudflare DNS-01 ACME and proxies to localhost:7780.

**Tech Stack:** NixOS modules, systemd, nginx, ACME/Cloudflare DNS-01, NumTide llm-agents.nix overlay

**Spec:** `docs/superpowers/specs/2026-04-03-vibe-kanban-service-design.md`

**Verified from binary:** The `vibe-kanban` binary accepts `--host` and `--port` CLI flags (confirmed via `strings` on the Nix store path). The `VK_ALLOWED_ORIGINS` environment variable is confirmed present. The binary calls `xdg-open` on startup — suppressed via `BROWSER=true`.

---

### Task 1: Create the vibe-kanban NixOS module

**Files:**
- Create: `modules/nixos/vibe-kanban.nix`

**Reference files:**
- `modules/nixos/forgejo.nix` — same ACME + nginx pattern
- `modules/nixos/greenlight.nix` — same ACME + nginx pattern
- `modules/nixos/nginx.nix` — shared nginx + ACME defaults

- [ ] **Step 1: Create `modules/nixos/vibe-kanban.nix`**

```nix
{ config, lib, pkgs, ... }:

{
  # Systemd service for Vibe Kanban
  systemd.services.vibe-kanban = {
    description = "Vibe Kanban - AI Agent Management Board";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    environment = {
      # Suppress browser auto-open in headless systemd context
      BROWSER = "true";
      # Allow WebSocket connections through the reverse proxy
      VK_ALLOWED_ORIGINS = "https://vibe-kanban.jordangarrison.dev";
    };

    serviceConfig = {
      Type = "exec";
      User = "jordangarrison";
      Group = "users";
      WorkingDirectory = "/home/jordangarrison";
      ExecStart = "${pkgs.llm-agents.vibe-kanban}/bin/vibe-kanban --host 127.0.0.1 --port 7780";
      Restart = "on-failure";
      RestartSec = 5;

      # Allow access to user's home for git repos, SSH keys, dev tools
      ProtectHome = false;
    };
  };

  # ACME certificate via Cloudflare DNS-01 (defaults from nginx.nix)
  security.acme.certs."vibe-kanban.jordangarrison.dev" = {
    group = "nginx";
  };

  # Nginx reverse proxy
  services.nginx.virtualHosts."vibe-kanban.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "vibe-kanban.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://localhost:7780";
      proxyWebsockets = true;
    };
  };
}
```

- [ ] **Step 2: Verify Nix syntax**

```bash
nix-instantiate --parse modules/nixos/vibe-kanban.nix > /dev/null
```
Expected: No errors (syntax is valid). Full evaluation happens in Task 2 after wiring into flake.nix.

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/vibe-kanban.nix
git commit -m "feat: add vibe-kanban NixOS service module

Wraps pkgs.llm-agents.vibe-kanban as a systemd service running as
jordangarrison on port 7780 with nginx reverse proxy and ACME cert
at vibe-kanban.jordangarrison.dev."
```

---

### Task 2: Wire the module into the endeavour host configuration

**Files:**
- Modify: `flake.nix` — add module import to endeavour's modules list

**Reference:** Look at how `./modules/nixos/greenlight.nix` (line 106) and `./modules/nixos/forgejo.nix` (line 109) are imported in the endeavour configuration.

- [ ] **Step 1: Add vibe-kanban module to endeavour's modules list**

In `flake.nix`, within the `endeavour` nixosConfiguration modules list, add the import after the existing service modules (after `./modules/nixos/forgejo-runner.nix`):

```nix
./modules/nixos/vibe-kanban.nix
```

The line should go around line 111 (after `forgejo-runner.nix`, before `virtualization.nix`), keeping service modules grouped together.

- [ ] **Step 2: Verify the full configuration evaluates**

Run from the nix-config repo root:
```bash
nix eval .#nixosConfigurations.endeavour.config.systemd.services.vibe-kanban.serviceConfig.ExecStart 2>&1
```
Expected: Should print the ExecStart string containing the vibe-kanban store path and `--host 127.0.0.1 --port 7780`.

- [ ] **Step 3: Build the configuration (dry run)**

```bash
nh os build .
```
Expected: Build succeeds. This confirms the module integrates correctly with all other endeavour modules.

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat: enable vibe-kanban service on endeavour"
```

---

### Task 3: Verify and deploy

This task must be run on the `endeavour` machine.

- [ ] **Step 1: Test the configuration**

```bash
nh os test .
```
Expected: Configuration applies successfully. The vibe-kanban service should start.

- [ ] **Step 2: Check service status**

```bash
systemctl status vibe-kanban
```
Expected: Active (running), no errors.

- [ ] **Step 3: Test local connectivity**

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:7780
```
Expected: `200` (or a redirect status like `301`/`302`).

- [ ] **Step 4: Switch to the new configuration**

```bash
nh os switch .
```
Expected: Switch succeeds, service persists across boot.

- [ ] **Step 5: Check where state is persisted**

```bash
find /home/jordangarrison -maxdepth 3 -name "*.vibe-kanban*" -o -name ".vibe-kanban" -type d 2>/dev/null
ls -la /home/jordangarrison/.vibe-kanban/ 2>/dev/null || echo "No .vibe-kanban directory found — check working directory for state files"
```
Document where profiles, workspace state, and caches land for future reference.

- [ ] **Step 6: Verify ACME cert and nginx**

Note: This requires the DNS record to exist first (see Task 4).

```bash
curl -s -o /dev/null -w "%{http_code}" https://vibe-kanban.jordangarrison.dev
```
Expected: `200` with valid TLS.

**Troubleshooting — WebSocket timeouts:** If idle WebSocket connections drop after ~60s, add `proxy_read_timeout` to the nginx location in `modules/nixos/vibe-kanban.nix`:
```nix
locations."/" = {
  proxyPass = "http://localhost:7780";
  proxyWebsockets = true;
  extraConfig = ''
    proxy_read_timeout 3600s;
  '';
};
```

---

### Task 4: Add Cloudflare DNS record (manual)

This task is performed in the Cloudflare dashboard, not in code.

- [ ] **Step 1: Add DNS record**

In the Cloudflare dashboard for `jordangarrison.dev`, add a DNS record for `vibe-kanban` pointing to the endeavour machine. Follow the same pattern as `greenlight.jordangarrison.dev` and `forgejo.jordangarrison.dev` (likely an A record pointing to the Tailscale IP, or a CNAME).

- [ ] **Step 2: Verify resolution**

```bash
dig vibe-kanban.jordangarrison.dev
```
Expected: Resolves to the endeavour IP.

- [ ] **Step 3: Verify end-to-end HTTPS**

```bash
curl -s -o /dev/null -w "%{http_code}" https://vibe-kanban.jordangarrison.dev
```
Expected: `200` with valid TLS certificate.

- [ ] **Step 4: Open in browser and verify git repo access**

Navigate to `https://vibe-kanban.jordangarrison.dev` in a browser and verify:
- The Vibe Kanban UI loads
- It can see local git repositories
- Creating a workspace functions correctly
