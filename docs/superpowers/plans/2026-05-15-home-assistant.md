# Home Assistant on endeavour — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up Home Assistant Core as a native NixOS service on `endeavour`, fronted by nginx at `hass.garrisonsbygrace.com`, exposing devices to Apple Home via HomeKit Bridge, with a daily SQLite-online backup to `/var/backups/hass`.

**Architecture:** New module `modules/nixos/home-assistant.nix` wired into endeavour's flake entry, alongside other self-hosted services. SQLite recorder, hybrid config (Nix-managed skeleton + UI for runtime state), nginx reverse proxy with existing ACME/Cloudflare DNS-01 setup, systemd timer for daily backup as the `hass` user.

**Tech Stack:** NixOS (nixos-unstable), `services.home-assistant`, `services.nginx`, `security.acme`, `systemd.tmpfiles.rules`, `systemd.services` / `systemd.timers`, `pkgs.writeShellApplication`, `pkgs.linkFarm`, `sqlite3`, `zstd`, `flarectl` (Cloudflare DNS).

**Spec:** [`docs/superpowers/specs/2026-05-15-home-assistant-design.md`](../specs/2026-05-15-home-assistant-design.md)

**Environment assumptions:**
- All `nh os build/test/switch` commands must be run on `endeavour` itself (`nh os` builds for current hostname). If working from another host, SSH in: `ssh endeavour` and `cd ~/dev/jordangarrison/nix-config` (or wherever the repo is mounted/cloned on endeavour).
- All `--no-nom` flags are mandatory per repo CLAUDE.md.
- `flarectl` is available globally on endeavour (wrapped with the Cloudflare token).
- Network: endeavour's Tailscale IP is `100.118.65.11`.

---

## File Structure

| File | Purpose |
|---|---|
| `modules/nixos/home-assistant.nix` | **CREATE** — Module: service config, nginx vhost, ACME cert, firewall, tmpfiles, backup unit + timer. |
| `modules/nixos/home-assistant/packages/homekit-bridge.yaml` | **CREATE** — HomeKit Bridge YAML (config + entity filter). Symlinked into `/var/lib/hass/packages/` at runtime. |
| `flake.nix` | **MODIFY** — Add the new module to endeavour's module list. Insertion point: after `./modules/nixos/jellyfin.nix` (line ~133). |
| `/var/lib/hass-secrets/secrets.yaml` | **CREATE on endeavour** (not in git) — HomeKit PIN. Owned `hass:hass 0600`. |

Each file has one clear responsibility:
- The `.nix` module is the full system declaration (service, proxy, certs, backup) for one feature, matching how `jellyfin.nix` does it.
- The package YAML is config-data only — no logic, no secrets (PIN is a `!secret` reference).
- `flake.nix` mod is one line.
- The on-host secret file is the only piece that can't live in git.

---

## Task 1 — Skeleton module + flake wiring (no service yet)

**Goal of this task:** Land an empty NixOS module wired into the endeavour flake entry, prove the flake still builds. This is the "scaffold green" checkpoint — every later task is incremental on a known-good base.

**Files:**
- Create: `modules/nixos/home-assistant.nix`
- Modify: `flake.nix:133` (insert new module path)

---

- [ ] **Step 1.1: Pre-flight — confirm clean build on current main**

Run on endeavour, from the repo root:
```bash
cd ~/dev/jordangarrison/nix-config
git status
nh os build . --no-nom
```

Expected:
- `git status`: clean (or only the `flake.lock` already-modified line that's in the working tree)
- `nh os build`: completes, ends with a path like `/nix/store/...-nixos-system-endeavour-...`. No `error:` lines.

If this fails, **stop**. The base must be green before adding anything.

- [ ] **Step 1.2: Create the empty module file**

Create `modules/nixos/home-assistant.nix` with this exact content:

```nix
{ config, lib, pkgs, ... }:

{
  # Home Assistant on endeavour
  # Spec: docs/superpowers/specs/2026-05-15-home-assistant-design.md
  # Implementation grows task-by-task in
  # docs/superpowers/plans/2026-05-15-home-assistant.md
}
```

(Empty module body. Lands the file path so later tasks have somewhere to edit.)

- [ ] **Step 1.3: Wire the module into flake.nix**

Edit `flake.nix`. Find this block (around line 133):

```nix
            ./modules/nixos/nginx.nix
            ./modules/nixos/jellyfin.nix
            ./modules/nixos/forgejo.nix
```

Insert `./modules/nixos/home-assistant.nix` directly after `./modules/nixos/jellyfin.nix`:

```nix
            ./modules/nixos/nginx.nix
            ./modules/nixos/jellyfin.nix
            ./modules/nixos/home-assistant.nix
            ./modules/nixos/forgejo.nix
```

- [ ] **Step 1.4: Verify the flake still builds**

```bash
nh os build . --no-nom
```

Expected: completes successfully, no errors. (The module is a no-op, so this just proves the wiring is valid Nix.)

- [ ] **Step 1.5: Commit**

```bash
git add modules/nixos/home-assistant.nix flake.nix
git commit -m "feat(nixos): scaffold home-assistant module on endeavour"
```

---

## Task 2 — Enable HA service with minimal config

**Goal:** HA service starts on endeavour, listens on loopback only, basic config in place. No nginx, no HomeKit, no backup yet. Verifiable: systemd unit active, port 8123 reachable via local loopback / SSH-forwarded port.

**Files:**
- Modify: `modules/nixos/home-assistant.nix`

---

- [ ] **Step 2.1: Pre-test — confirm HA isn't present on endeavour**

```bash
ssh endeavour 'systemctl cat home-assistant.service 2>&1 | head -5'
```

Expected output contains: `No files found for home-assistant.service` (or systemd reports the unit doesn't exist).

This is the "test that fails first" — proves the change in this task is what brings HA into existence.

- [ ] **Step 2.2: Replace the module body with minimal HA service config**

Replace the contents of `modules/nixos/home-assistant.nix` with:

```nix
{ config, lib, pkgs, ... }:

{
  # Home Assistant on endeavour
  # Spec: docs/superpowers/specs/2026-05-15-home-assistant-design.md

  services.home-assistant = {
    enable          = true;
    openFirewall    = false;             # nginx will be the only ingress (added in Task 3)
    configWritable  = true;              # HA can edit configuration.yaml at runtime;
                                         # nh os switch reasserts the Nix-rendered version.
    extraComponents = [
      "default_config"
      "met"
      "backup"
    ];
    config = {
      homeassistant = {
        name         = "GarrisonsByGrace Home";
        time_zone    = config.time.timeZone;
        unit_system  = "imperial";
        internal_url = "https://hass.garrisonsbygrace.com";
        external_url = "https://hass.garrisonsbygrace.com";
        # HomeKit Bridge YAML will land in /var/lib/hass/packages/ via tmpfiles symlink in Task 4
        packages     = "!include_dir_named packages";
      };
      default_config = {};
      http = {
        server_host         = [ "127.0.0.1" "::1" ];   # loopback only
        use_x_forwarded_for = true;
        trusted_proxies     = [ "127.0.0.1" "::1" ];
      };
      recorder = {
        purge_keep_days = 10;
      };
    };
  };

  # Bootstrap dirs that later tasks (and HA itself) will populate.
  # /var/lib/hass-secrets exists now so secrets.yaml has a home in Task 4.
  # /var/lib/hass/packages will be made a symlink in Task 4 (don't pre-create as a dir).
  systemd.tmpfiles.rules = [
    "d /var/lib/hass-secrets 0750 hass hass -"
  ];
}
```

Notes the engineer may want to know:
- `extraComponents` is intentionally short. The NixOS module auto-parses `services.home-assistant.config` and pulls Python deps for components it sees in there (`default_config`, `http`, `recorder`, etc.). Listing them again is harmless but redundant. We list `met`, `backup`, and `default_config` explicitly to be safe; `homekit` joins this list in Task 4.
- `homeassistant.packages = "!include_dir_named packages"` references a directory that does NOT exist yet. HA will log a warning at startup until Task 4 creates the symlink. That's expected. The service still starts.
- `time_zone` comes from `config.time.timeZone` which is set elsewhere in the endeavour configuration — no hardcoding needed.

- [ ] **Step 2.3: Build**

```bash
nh os build . --no-nom
```

Expected: succeeds. If it errors with something like "the option `services.home-assistant.config.homeassistant.packages` is not of the expected type" or similar, the rendering of `!include_dir_named` is the most likely culprit — confirm the string is exact (`"!include_dir_named packages"`).

- [ ] **Step 2.4: Test-activate (non-permanent)**

```bash
nh os test . --no-nom
```

Expected: completes, the new HA unit is now active. `nh os test` activates without bootloader update — a reboot would revert.

- [ ] **Step 2.5: Verify HA service is up**

```bash
systemctl status home-assistant.service
```

Expected:
- `Loaded: loaded (...home-assistant.service; enabled; ...)`
- `Active: active (running) since ...`
- No tracebacks in recent log lines.

Then check HA's own log:
```bash
journalctl -u home-assistant.service -n 100 --no-pager | tail -40
```

Look for `Home Assistant initialized in ...s` near the bottom. Acceptable warnings: "Component packages not found" if the include dir doesn't exist yet — fine, Task 4 fixes it.

If you see a Python traceback or `Setup failed for ...`, stop and diagnose before continuing.

- [ ] **Step 2.6: Verify HA is reachable on loopback**

From endeavour:
```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8123
```

Expected: `200` (HA's onboarding page).

Confirm it is NOT reachable on any other interface (defense in depth):
```bash
ss -tlnp | grep :8123
```

Expected: only `127.0.0.1:8123` and/or `[::1]:8123` listeners — nothing on `0.0.0.0` or the Tailscale IP.

- [ ] **Step 2.7: Complete HA onboarding via SSH-forwarded port**

From your workstation:
```bash
ssh -L 8123:127.0.0.1:8123 endeavour
# Leave the SSH session open.
```

In a browser on your workstation, go to `http://localhost:8123`. HA's onboarding wizard should load. Walk through:
1. Create owner account (record credentials in 1Password under "Home Assistant — owner account").
2. Set location (Garrison home address) — used for sunrise/sunset, weather, etc.
3. Decline analytics if you prefer (or accept — your call).
4. Skip device discovery for now; we'll add integrations after the proxy is up.

Why now and not after the proxy: this avoids the "onboarding race" where a public HTTPS URL serves an unprotected setup wizard.

When done, you can close the SSH tunnel.

- [ ] **Step 2.8: Commit**

```bash
git add modules/nixos/home-assistant.nix
git commit -m "feat(nixos): enable home-assistant service on endeavour"
```

---

## Task 3 — nginx + ACME + Cloudflare DNS

**Goal:** `https://hass.garrisonsbygrace.com` reachable from Tailscale, valid cert, HA UI works behind the proxy (including websockets).

**Files:**
- Modify: `modules/nixos/home-assistant.nix`

External actions:
- One Cloudflare DNS record creation via `flarectl`.

---

- [ ] **Step 3.1: Pre-test — confirm DNS and cert don't exist yet**

```bash
# DNS doesn't resolve
dig +short hass.garrisonsbygrace.com
# expect: empty output

# No cert directory on endeavour
ssh endeavour 'sudo ls /var/lib/acme/hass.garrisonsbygrace.com 2>&1'
# expect: "No such file or directory"

# Nginx vhost not present
ssh endeavour 'sudo nginx -T 2>/dev/null | grep -c "hass.garrisonsbygrace.com"'
# expect: 0
```

- [ ] **Step 3.2: Create the Cloudflare DNS A record**

Run on endeavour (where the wrapped `flarectl` has the token):

```bash
flarectl dns create \
  --zone garrisonsbygrace.com \
  --name hass \
  --type A \
  --content 100.118.65.11 \
  --ttl 1
```

Expected output: a JSON-ish record confirmation with `type=A`, `content=100.118.65.11`, `proxied=false`.

Verify:
```bash
dig +short hass.garrisonsbygrace.com
# expect: 100.118.65.11
```

(DNS-01 ACME challenge for the cert doesn't actually need the A record — only the `_acme-challenge.hass.garrisonsbygrace.com` TXT, which `lego`/the ACME module creates itself. But you need the A record before any client can resolve the hostname. Creating it now is convenient.)

- [ ] **Step 3.3: Add nginx + ACME + firewall to the module**

Append to `modules/nixos/home-assistant.nix` — keep everything from Task 2, add these new blocks before the closing `}`:

```nix
  security.acme.certs."hass.garrisonsbygrace.com" = {
    group = "nginx";
  };

  services.nginx.virtualHosts."hass.garrisonsbygrace.com" = {
    forceSSL    = true;
    useACMEHost = "hass.garrisonsbygrace.com";
    locations."/" = {
      proxyPass       = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout  86400;
      '';
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 21063 ];   # HomeKit Bridge (Task 4) — LAN only, mDNS-discovered
    allowedUDPPorts = [ 5353 ];    # mDNS / zeroconf for HA's built-in responder
  };
```

Notes:
- `proxyWebsockets = true` makes nginx pass `Upgrade`/`Connection` headers. Without it the HA UI loads but is functionally dead (no live updates).
- `proxy_buffering off` is critical for HA's streaming log views and update progress.
- `proxy_read_timeout 86400` (24h) keeps long-lived websockets from dropping.
- `useACMEHost` references the cert from the `security.acme.certs` block. `forceSSL = true` redirects HTTP → HTTPS.
- Firewall opens HomeKit + mDNS now even though HomeKit Bridge YAML lands in Task 4 — opening early is fine; the bridge isn't listening yet so nothing to expose.

- [ ] **Step 3.4: Build**

```bash
nh os build . --no-nom
```

Expected: succeeds. Common pitfalls:
- Indentation in the appended block. Should be consistent with the rest (Nix doesn't care about indentation but the file should stay readable).
- Closing brace placement. The whole module is one top-level `{ ... }`.

- [ ] **Step 3.5: Test-activate**

```bash
nh os test . --no-nom
```

Expected: succeeds. ACME will attempt to issue the cert in the background.

- [ ] **Step 3.6: Wait for the cert to issue, verify**

```bash
sudo journalctl -u 'acme-hass.garrisonsbygrace.com.service' -f --no-pager
```

Wait for a line like `Finished renewing cert for hass.garrisonsbygrace.com` or `Certificate has been renewed successfully`. Ctrl-C once you see it.

Then:
```bash
sudo ls /var/lib/acme/hass.garrisonsbygrace.com/
# expect: cert.pem chain.pem fullchain.pem key.pem ...
```

Then verify reload happened:
```bash
sudo nginx -T 2>/dev/null | grep "server_name hass.garrisonsbygrace.com"
# expect: 1+ matches
```

- [ ] **Step 3.7: Verify HTTPS path end-to-end**

From your workstation (with Tailscale connected to your tailnet):

```bash
curl -sS -o /dev/null -w 'http=%{http_code} time=%{time_total}s\n' \
  https://hass.garrisonsbygrace.com
```

Expected: `http=200`, sub-second time. Cert valid (curl doesn't `-k`).

Open `https://hass.garrisonsbygrace.com` in a browser. HA's login page should render. Log in with the owner account you created in Step 2.7.

If you get `400 Bad Request`: the `trusted_proxies` config is wrong. Re-check that `127.0.0.1` is in both `server_host` and `trusted_proxies`, and `use_x_forwarded_for = true`.

If you get `502 Bad Gateway`: HA itself isn't listening on `127.0.0.1:8123` anymore. Check `systemctl status home-assistant`.

If the UI loads but is "frozen" (no live updates): websockets aren't working. Re-check `proxyWebsockets = true`.

- [ ] **Step 3.8: Commit**

```bash
git add modules/nixos/home-assistant.nix
git commit -m "feat(nixos): expose home-assistant at hass.garrisonsbygrace.com via nginx"
```

---

## Task 4 — HomeKit Bridge + secrets

**Goal:** HA exposes a HomeKit Bridge that pairs with the iPhone Home app; HomePods then auto-discover HA-managed devices.

**Files:**
- Create: `modules/nixos/home-assistant/packages/homekit-bridge.yaml`
- Modify: `modules/nixos/home-assistant.nix`

On-host (manual):
- Create `/var/lib/hass-secrets/secrets.yaml` with the HomeKit PIN.

---

- [ ] **Step 4.1: Pre-test — confirm HomeKit Bridge isn't running**

```bash
ssh endeavour 'ss -tlnp | grep 21063'
# expect: empty
```

- [ ] **Step 4.2: Seed the secrets file on endeavour**

Pick an 8-digit PIN in Apple's `XXX-XX-XXX` format. Example: `031-45-154`. Use a different value — don't copy the example. Write it down somewhere reachable (you'll need it on every paired Apple device).

```bash
ssh endeavour
sudo mkdir -p /var/lib/hass-secrets
sudo chown hass:hass /var/lib/hass-secrets
sudo chmod 0750 /var/lib/hass-secrets
sudo $EDITOR /var/lib/hass-secrets/secrets.yaml
```

Paste exactly (substitute your chosen PIN):

```yaml
# /var/lib/hass-secrets/secrets.yaml
# HomeKit Bridge pairing PIN. Format: NNN-NN-NNN.
homekit_pin: "031-45-154"
```

Save and:

```bash
sudo chown hass:hass /var/lib/hass-secrets/secrets.yaml
sudo chmod 0600 /var/lib/hass-secrets/secrets.yaml
```

Stash the PIN in 1Password under "Home Assistant — HomeKit Bridge".

- [ ] **Step 4.3: Create the HomeKit Bridge package file**

Create `modules/nixos/home-assistant/packages/homekit-bridge.yaml` with this exact content:

```yaml
homekit:
  - name: GarrisonsByGrace Bridge
    port: 21063
    pin: !secret homekit_pin
    filter:
      include_domains:
        - light
        - switch
        - sensor
        - binary_sensor
        - climate
        - cover
        - lock
        - media_player
    # Start permissive; tighten with include_entities later once HA
    # discovers actual devices via UI integration flows.
```

Notes:
- The `port: 21063` is pinned so the firewall rule from Task 3 is stable.
- `pin: !secret homekit_pin` references the seeded `secrets.yaml`.
- `filter:` controls which HA entities the bridge advertises to Apple Home. Restrictive enough to keep helper / scratch entities out by default.

- [ ] **Step 4.4: Replace the module with the Task 4 version**

Replace the entire contents of `modules/nixos/home-assistant.nix` with this complete file:

```nix
{ config, lib, pkgs, ... }:

let
  haPackages = pkgs.linkFarm "hass-packages" [
    { name = "homekit-bridge.yaml";
      path = ./home-assistant/packages/homekit-bridge.yaml; }
  ];
in
{
  # Home Assistant on endeavour
  # Spec: docs/superpowers/specs/2026-05-15-home-assistant-design.md

  services.home-assistant = {
    enable          = true;
    openFirewall    = false;
    configWritable  = true;
    extraComponents = [
      "default_config"
      "met"
      "homekit"
      "backup"
    ];
    config = {
      homeassistant = {
        name         = "GarrisonsByGrace Home";
        time_zone    = config.time.timeZone;
        unit_system  = "imperial";
        internal_url = "https://hass.garrisonsbygrace.com";
        external_url = "https://hass.garrisonsbygrace.com";
        packages     = "!include_dir_named packages";
      };
      default_config = {};
      http = {
        server_host         = [ "127.0.0.1" "::1" ];
        use_x_forwarded_for = true;
        trusted_proxies     = [ "127.0.0.1" "::1" ];
      };
      recorder = {
        purge_keep_days = 10;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d  /var/lib/hass-secrets       0750 hass hass -"
    "L+ /var/lib/hass/packages      -    -    -    - ${haPackages}"
    "L+ /var/lib/hass/secrets.yaml  -    -    -    - /var/lib/hass-secrets/secrets.yaml"
  ];

  security.acme.certs."hass.garrisonsbygrace.com" = {
    group = "nginx";
  };

  services.nginx.virtualHosts."hass.garrisonsbygrace.com" = {
    forceSSL    = true;
    useACMEHost = "hass.garrisonsbygrace.com";
    locations."/" = {
      proxyPass       = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout  86400;
      '';
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 21063 ];   # HomeKit Bridge — LAN only, mDNS-discovered
    allowedUDPPorts = [ 5353 ];    # mDNS / zeroconf for HA's built-in responder
  };
}
```

Key changes from Task 3:
- Wraps the file in a `let ... in` binding for `haPackages` (will grow to include `hassBackup` in Task 5).
- Adds `homekit` to `extraComponents`.
- Adds two new `systemd.tmpfiles.rules` entries: `L+` symlinks for the `packages/` linkFarm and `secrets.yaml`.
- `L+` (capital L plus) means "force create symlink, replacing whatever's there." Important because HA's initial run may have created an empty `packages/` directory or empty `secrets.yaml` that this symlink needs to overwrite.

- [ ] **Step 4.5: Build**

```bash
nh os build . --no-nom
```

Expected: succeeds. If you get an error about `homekit-bridge.yaml` not being present, double-check the file exists at the path referenced by `linkFarm`: `modules/nixos/home-assistant/packages/homekit-bridge.yaml`.

- [ ] **Step 4.6: Test-activate**

```bash
nh os test . --no-nom
```

Expected: succeeds. HA service should restart automatically because its config changed.

- [ ] **Step 4.7: Verify the symlinks and HomeKit Bridge are live**

```bash
ssh endeavour
ls -la /var/lib/hass/packages /var/lib/hass/secrets.yaml
```

Expected:
- `/var/lib/hass/packages` → symlink to `/nix/store/...-hass-packages`
- `/var/lib/hass/secrets.yaml` → symlink to `/var/lib/hass-secrets/secrets.yaml`

```bash
sudo cat /var/lib/hass/packages/homekit-bridge.yaml
```

Expected: the YAML you wrote.

```bash
sudo systemctl status home-assistant
journalctl -u home-assistant -n 50 --no-pager | tail -30
```

Look for log lines about HomeKit bridge starting. You should see something like:
```
Setup of domain homekit took ...
HomeKit Bridge 'GarrisonsByGrace Bridge' is now running. Pairing setup needed.
```

```bash
ss -tlnp | grep 21063
```

Expected: a listener on `0.0.0.0:21063` (or `[::]:21063`).

- [ ] **Step 4.8: Pair from iPhone**

On iPhone (must be on the same physical/local network as endeavour, not just Tailscale — HomeKit accessory protocol is L2/mDNS):

1. Open Home app → tap `+` (top right) → Add Accessory.
2. Tap "More options" (small text below the camera viewfinder).
3. Wait a few seconds. "GarrisonsByGrace Bridge" should appear under "Nearby Accessories" or "Bridges".
4. Tap it. Enter the PIN from Step 4.2 in the `NNN-NN-NNN` format.
5. Assign to a room ("default" is fine).
6. HomePods that share your Home will auto-pick-up the bridge — no per-device pairing.

If the bridge doesn't appear:
- Confirm iPhone is on the **same LAN as endeavour** (not just Tailscale).
- Confirm firewall rules from Task 3 are live: `sudo iptables -L INPUT -n | grep -E '21063|5353'`.
- Confirm mDNS listener is up: `sudo ss -ulnp | grep 5353`.
- Check HA logs: `journalctl -u home-assistant | grep -i homekit | tail -20`.

At this point HA likely has no integrations / devices yet, so the bridge is "empty." That's fine — pairing the empty bridge now means future devices will flow into Apple Home as soon as you add HA integrations.

- [ ] **Step 4.9: Commit**

```bash
git add \
  modules/nixos/home-assistant.nix \
  modules/nixos/home-assistant/packages/homekit-bridge.yaml
git commit -m "feat(nixos): add HomeKit Bridge to home-assistant"
```

(`secrets.yaml` is on the host, not in git — `.gitignore` already excludes anything under `/var/`, but double-check with `git status` that no stray secret file is staged.)

---

## Task 5 — Daily SQLite-online backup

**Goal:** `hass-backup.service` produces a daily `tar.zst` of HA state under `/var/backups/hass/`, keeps 7 days, scheduled by `hass-backup.timer`. Uses SQLite's online `.backup` API so HA never has to stop.

**Files:**
- Modify: `modules/nixos/home-assistant.nix`

---

- [ ] **Step 5.1: Pre-test — confirm backup unit and dir don't exist**

```bash
ssh endeavour 'systemctl cat hass-backup.timer 2>&1 | head -3'
# expect: "No files found for hass-backup.timer"

ssh endeavour 'ls -ld /var/backups/hass 2>&1'
# expect: "No such file or directory"
```

- [ ] **Step 5.2: Replace the module with the Task 5 version (adds backup script + service + timer)**

Replace the entire contents of `modules/nixos/home-assistant.nix` with this complete file:

```nix
{ config, lib, pkgs, ... }:

let
  haPackages = pkgs.linkFarm "hass-packages" [
    { name = "homekit-bridge.yaml";
      path = ./home-assistant/packages/homekit-bridge.yaml; }
  ];

  hassBackup = pkgs.writeShellApplication {
    name = "hass-backup";
    runtimeInputs = with pkgs; [ sqlite zstd gnutar coreutils findutils ];
    text = ''
      set -euo pipefail
      stamp=$(date -u +%Y-%m-%dT%H-%M-%SZ)
      dest=/var/backups/hass
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      mkdir -p "$dest"

      # 1. online SQLite snapshot (atomic, no HA downtime)
      sqlite3 /var/lib/hass/home-assistant_v2.db \
        ".backup '$work/home-assistant_v2.db'"

      # 2. tar everything else minus the live DB / WAL / SHM, then append
      #    the snapshot into the same archive in one pass.
      tar --create \
          --file - \
          --directory /var/lib/hass \
          --exclude='home-assistant_v2.db' \
          --exclude='home-assistant_v2.db-wal' \
          --exclude='home-assistant_v2.db-shm' \
          --exclude='home-assistant.log*' \
          --exclude='deps' \
          . \
        | tar --append --file - --directory "$work" home-assistant_v2.db \
        | zstd -T0 -19 -o "$dest/hass-$stamp.tar.zst"

      # 3. prune archives older than 7 days
      find "$dest" -maxdepth 1 -name 'hass-*.tar.zst' -mtime +7 -delete

      # 4. emit size for journal
      ls -lh "$dest/hass-$stamp.tar.zst"
    '';
  };
in
{
  # Home Assistant on endeavour
  # Spec: docs/superpowers/specs/2026-05-15-home-assistant-design.md

  services.home-assistant = {
    enable          = true;
    openFirewall    = false;
    configWritable  = true;
    extraComponents = [
      "default_config"
      "met"
      "homekit"
      "backup"
    ];
    config = {
      homeassistant = {
        name         = "GarrisonsByGrace Home";
        time_zone    = config.time.timeZone;
        unit_system  = "imperial";
        internal_url = "https://hass.garrisonsbygrace.com";
        external_url = "https://hass.garrisonsbygrace.com";
        packages     = "!include_dir_named packages";
      };
      default_config = {};
      http = {
        server_host         = [ "127.0.0.1" "::1" ];
        use_x_forwarded_for = true;
        trusted_proxies     = [ "127.0.0.1" "::1" ];
      };
      recorder = {
        purge_keep_days = 10;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d  /var/lib/hass-secrets       0750 hass hass -"
    "d  /var/backups/hass           0750 hass hass -"
    "L+ /var/lib/hass/packages      -    -    -    - ${haPackages}"
    "L+ /var/lib/hass/secrets.yaml  -    -    -    - /var/lib/hass-secrets/secrets.yaml"
  ];

  security.acme.certs."hass.garrisonsbygrace.com" = {
    group = "nginx";
  };

  services.nginx.virtualHosts."hass.garrisonsbygrace.com" = {
    forceSSL    = true;
    useACMEHost = "hass.garrisonsbygrace.com";
    locations."/" = {
      proxyPass       = "http://127.0.0.1:8123";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_buffering off;
        proxy_read_timeout  86400;
      '';
    };
  };

  networking.firewall = {
    allowedTCPPorts = [ 21063 ];   # HomeKit Bridge — LAN only, mDNS-discovered
    allowedUDPPorts = [ 5353 ];    # mDNS / zeroconf for HA's built-in responder
  };

  systemd.services.hass-backup = {
    description = "Daily Home Assistant backup";
    serviceConfig = {
      Type      = "oneshot";
      ExecStart = "${hassBackup}/bin/hass-backup";
      User      = "hass";
      Group     = "hass";

      ProtectSystem    = "strict";
      ProtectHome      = true;
      PrivateTmp       = true;
      NoNewPrivileges  = true;
      ReadWritePaths   = [ "/var/backups/hass" ];

      Nice              = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.hass-backup = {
    description = "Daily Home Assistant backup timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar         = "*-*-* 03:30:00";
      Persistent         = true;
      RandomizedDelaySec = "10m";
    };
  };

  environment.systemPackages = [ hassBackup ];
}
```

Key changes from Task 4:
- `let` block grows to include `hassBackup`.
- `systemd.tmpfiles.rules` gains one entry: `d /var/backups/hass 0750 hass hass -`.
- Three new top-level attrs at the bottom: `systemd.services.hass-backup`, `systemd.timers.hass-backup`, `environment.systemPackages`.

Notes:
- `User = "hass"`: the backup process has the same access rights as HA itself — reads its own state dir, no privilege escalation.
- `ProtectSystem = "strict"` makes `/` read-only for the process; `ReadWritePaths = [ "/var/backups/hass" ]` re-opens only the backup dir for writes. `PrivateTmp = true` gives an isolated tmp so the work dir can't leak.
- `Persistent = true` runs the missed schedule at next boot if endeavour was off at 03:30.
- `environment.systemPackages = [ hassBackup ]` puts the `hass-backup` binary on `$PATH` for ad-hoc runs.

- [ ] **Step 5.3: Build**

```bash
nh os build . --no-nom
```

Expected: succeeds.

- [ ] **Step 5.4: Test-activate**

```bash
nh os test . --no-nom
```

Expected: succeeds. The new timer should activate immediately.

- [ ] **Step 5.5: Verify the timer is scheduled**

```bash
systemctl list-timers hass-backup.timer
```

Expected output includes a row for `hass-backup.timer` with a `NEXT` time at the next 03:30 (± 10 min jitter).

```bash
systemctl status hass-backup.timer
```

Expected: `Active: active (waiting)`.

- [ ] **Step 5.6: Run the backup manually once**

```bash
sudo systemctl start hass-backup.service
```

Wait a few seconds, then:

```bash
sudo systemctl status hass-backup.service
```

Expected: `Active: inactive (dead)` with `status=0/SUCCESS` and a recent `Process: ... ExecStart= ... (code=exited, status=0/SUCCESS)`.

Then:
```bash
journalctl -u hass-backup.service -n 30 --no-pager
ls -lh /var/backups/hass/
```

Expected: one `hass-YYYY-MM-DDTHH-MM-SSZ.tar.zst` file. For a fresh HA install with no real history, expect a few hundred KB to a couple of MB.

If the service fails, common causes:
- `sqlite3 .backup` permission error: `hass` user can't read the DB. Check `ls -l /var/lib/hass/home-assistant_v2.db` — should be `hass:hass`.
- `mkdir` / write permission error: check `/var/backups/hass` is owned `hass:hass` mode `0750` (created by tmpfiles).
- `systemd` blocked something: check `journalctl -u hass-backup` for "Permission denied" — `ProtectSystem=strict` might be too aggressive if you added more write paths than `ReadWritePaths` covers.

- [ ] **Step 5.7: Verify archive contents**

```bash
zstd -d -c /var/backups/hass/hass-*.tar.zst | tar -tf - | head -30
```

Expected: a list including at least `./` entries, `.storage/`, `home-assistant_v2.db`. No `home-assistant_v2.db-wal` or `home-assistant_v2.db-shm` (excluded). No `deps/` (excluded — big and regenerable).

- [ ] **Step 5.8: Commit**

```bash
git add modules/nixos/home-assistant.nix
git commit -m "feat(nixos): daily home-assistant backup with 7-day retention"
```

---

## Task 6 — Promote to permanent generation & acceptance walk

**Goal:** Commit the test-only activations as a permanent generation; walk the acceptance criteria from the spec.

**Files:** None modified.

---

- [ ] **Step 6.1: Switch (makes the test-activated config a real generation)**

```bash
nh os switch . --no-nom
```

This is the equivalent of "promote" — until now, every change was `nh os test`, which doesn't update the bootloader. `switch` does. After this, the HA config persists across reboots.

- [ ] **Step 6.2: Walk acceptance criteria from the spec**

For each, run the command and record pass/fail.

1. **HA service is active:**
   ```bash
   systemctl is-active home-assistant.service
   ```
   Expected: `active`

2. **HTTPS path works with a valid cert:**
   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' https://hass.garrisonsbygrace.com
   ```
   Expected: `200`

3. **Onboarding done — login page reachable:**
   Open `https://hass.garrisonsbygrace.com` in browser, log in with the owner account. UI loads, live updates work.

4. **HomeKit Bridge listening:**
   ```bash
   sudo ss -tlnp | grep 21063
   ```
   Expected: one listener.

5. **Bridge paired in Apple Home:**
   Open iPhone Home app → look for "GarrisonsByGrace Bridge" under Bridges. Tap it → status should be paired/online (devices may be 0 until you add integrations — fine for now).

6. **Backup unit produced an archive:**
   ```bash
   ls -lh /var/backups/hass/
   ```
   Expected: at least one `hass-*.tar.zst`.

7. **Backup timer scheduled:**
   ```bash
   systemctl list-timers hass-backup.timer
   ```
   Expected: row with a future `NEXT`.

8. **No new secrets in git:**
   ```bash
   git log --all -p -- '**/secrets.yaml' '**/homekit_pin*' 2>/dev/null | head -5
   ```
   Expected: empty.

9. **`nh flake check`** (light sanity check on the whole flake):
   ```bash
   cd ~/dev/jordangarrison/nix-config
   nh flake check
   ```
   Expected: no errors related to the new module.

- [ ] **Step 6.3: (Optional) Push**

```bash
git push
```

Do this when you're satisfied. The repo's policy is "never force push" — plain `git push` only.

---

## Out of scope (separate plans / specs)

- Thread/Matter Border Router (needs 802.15.4 USB stick — Silicon Labs or Nordic).
- Z-Wave (needs Z-Wave stick + `zwave-js-server`).
- MQTT broker (mosquitto) + Zigbee2MQTT.
- ESPHome service.
- Off-host backup replication (rsync `/var/backups/hass` to NAS / B2 / another host).
- Postgres recorder migration (defer until DB > ~2 GB).
- Custom integrations via `customComponents` (case-by-case).
- HA package version pinning (only if `nixpkgs-unstable` HA outpaces a custom component).
