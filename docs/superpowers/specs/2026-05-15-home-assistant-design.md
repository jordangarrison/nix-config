# Home Assistant on endeavour — Design

**Status**: Approved (pre-implementation)
**Date**: 2026-05-15
**Host**: endeavour (NixOS, services hub)
**Hostname**: `hass.garrisonsbygrace.com`

## Goal

Stand up Home Assistant Core as a native NixOS service on `endeavour`, alongside the other self-hosted services (forgejo, jellyfin, searx, etc.). Primary near-term use: extend the existing Apple Home setup (HomePods) with HA's automation engine, via the HomeKit Bridge integration. Set up so that as much as possible is managed in code (Nix + hand-authored YAML), while accepting that some integrations are UI-only in modern HA.

## Non-goals (deferred to follow-up specs)

- Thread/Matter Border Router (no 802.15.4 stick on endeavour yet)
- Z-Wave (no stick)
- MQTT broker (mosquitto), Zigbee2MQTT
- ESPHome compile/serve service
- Custom integrations via `customComponents` (case-by-case, as need arises)
- Postgres recorder migration (SQLite for now; revisit if DB > ~2 GB)
- Off-host backup replication (single-disk on endeavour for MVP)
- HA package version pinning (only if `nixpkgs-unstable` HA outpaces a custom component)

## Architecture

```
Apple Home (HomePods) ──(HomeKit accessory protocol over LAN/mDNS)──┐
                                                                    ▼
Tailscale clients ──(443)──► nginx ──(proxy_pass → 127.0.0.1:8123)──► home-assistant
                                  │                                        │
                              ACME (Cloudflare DNS-01)               recorder → SQLite
                              hass.garrisonsbygrace.com              /var/lib/hass/
                                                                          │
                                                            systemd timer ─┴─► /var/backups/hass/
                                                                              (daily, 7-day retention)
```

- Native NixOS service: `services.home-assistant`, no container, no VM.
- Public DNS A record → `100.118.65.11` (Tailscale IP for endeavour). Web UI is Tailscale-reachable only. Matches the existing pattern for forgejo, jellyfin, searx, greenlight, cg.
- HomeKit Bridge bypasses the proxy entirely — direct LAN + mDNS (HA's built-in zeroconf responder).

## Config style

**Hybrid: Nix-managed skeleton + UI for the rest.**

- Nix owns:
  - Service enablement, `extraComponents`, recorder config, http/auth, base `homeassistant:` block.
  - HomeKit Bridge config (it's YAML-friendly).
  - Hand-authored automations / scripts / packages that you want in code.
- HA UI owns:
  - Integration config flows (most modern integrations require UI setup).
  - Dashboards, ad-hoc automations, scenes, users — stored in `.storage/`.
- `configWritable = true`: HA can edit `configuration.yaml` at runtime so UI flows that touch yaml don't crash. **A `nh os switch` reasserts the Nix-rendered `configuration.yaml`** — code wins on deploy. This is intentional: it's the source-of-truth guarantee, with the trade that any UI-driven yaml edit is ephemeral.
- The irreplaceable state is `/var/lib/hass/.storage/` (UI integrations, dashboards, users, HomeKit pairing data). That's what the backup protects.

## File / module layout

```
nix-config/
├── flake.nix                              # add ./modules/nixos/home-assistant.nix to endeavour module list
├── modules/nixos/
│   └── home-assistant.nix                 # NEW — service + nginx + ACME + backup unit
└── modules/nixos/home-assistant/          # NEW — Nix-authored YAML, packaged via linkFarm
    ├── automations.yaml                   # initially empty / minimal
    ├── scripts.yaml                       # initially empty / minimal
    └── packages/
        └── homekit-bridge.yaml            # HomeKit Bridge config + entity filter

/var/lib/hass/                             # HA's state dir (HA-owned)
├── configuration.yaml                     # rendered from Nix; HA may edit at runtime, reasserted on switch
├── packages/                              # symlink → nix store linkFarm
├── automations.yaml                       # symlink → nix store
├── scripts.yaml                           # symlink → nix store
├── secrets.yaml                           # symlink → /var/lib/hass-secrets/secrets.yaml
├── .storage/                              # UI-managed state (irreplaceable)
├── home-assistant_v2.db                   # recorder SQLite
└── home-assistant.log

/var/lib/hass-secrets/                     # out-of-band secrets, owned hass:hass 0750
└── secrets.yaml                           # !secret source, mode 0600

/var/backups/hass/                         # FHS backup location, owned hass:hass 0750
└── hass-YYYY-MM-DDTHH-MM-SSZ.tar.zst      # daily, 7-day retention
```

Includes are wired with `systemd.tmpfiles.rules` symlinks because HA resolves `!include` paths relative to `configDir` (`/var/lib/hass`), not the nix store. The HA process never has to know the YAML lives in `/nix/store/...`.

## NixOS module — full shape

```nix
# modules/nixos/home-assistant.nix
{ config, lib, pkgs, ... }:

let
  haPackages = pkgs.linkFarm "hass-packages" [
    { name = "homekit-bridge.yaml";
      path = ./home-assistant/packages/homekit-bridge.yaml; }
    # add more package files here as the config grows
  ];
  haAutomations = ./home-assistant/automations.yaml;
  haScripts     = ./home-assistant/scripts.yaml;

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

      # online SQLite snapshot (atomic, no HA downtime)
      sqlite3 /var/lib/hass/home-assistant_v2.db \
        ".backup '$work/home-assistant_v2.db'"

      # tar everything else minus the live DB / WAL / SHM, then append snapshot
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

      # prune > 7 days
      find "$dest" -maxdepth 1 -name 'hass-*.tar.zst' -mtime +7 -delete

      ls -lh "$dest/hass-$stamp.tar.zst"
    '';
  };
in
{
  services.home-assistant = {
    enable          = true;
    openFirewall    = false;             # nginx fronts the web UI
    configWritable  = true;              # HA can edit at runtime, rebuild reasserts
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
      };
      default_config = {};
      http = {
        server_host         = [ "127.0.0.1" "::1" ];   # nginx is only ingress
        use_x_forwarded_for = true;
        trusted_proxies     = [ "127.0.0.1" "::1" ];
      };
      recorder = {
        purge_keep_days = 10;
        # exclude: tune later as entity churn grows
      };
      # split-config: pull in nix-managed yaml dirs/files
      homeassistant.packages = "!include_dir_named packages";
      automation = "!include automations.yaml";
      script     = "!include scripts.yaml";
    };
  };

  systemd.tmpfiles.rules = [
    "d  /var/lib/hass-secrets           0750 hass hass -"
    "d  /var/backups/hass               0750 hass hass -"
    "L+ /var/lib/hass/packages          -    -    -    - ${haPackages}"
    "L+ /var/lib/hass/automations.yaml  -    -    -    - ${haAutomations}"
    "L+ /var/lib/hass/scripts.yaml      -    -    -    - ${haScripts}"
    "L+ /var/lib/hass/secrets.yaml      -    -    -    - /var/lib/hass-secrets/secrets.yaml"
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
    allowedUDPPorts = [ 5353 ];    # mDNS / zeroconf (HA's own responder)
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

### Per-decision rationale

| Setting | Why |
|---|---|
| `openFirewall = false` + `http.server_host = [ "127.0.0.1" "::1" ]` | nginx is the only ingress; nothing on LAN/Tailscale can reach 8123 directly. Defense in depth. |
| `use_x_forwarded_for = true` + `trusted_proxies = [ "127.0.0.1" "::1" ]` | HA returns 400 behind a reverse proxy without this. |
| `configWritable = true` | Some HA flows write `configuration.yaml`. `false` would crash them. The "code wins on deploy" property is preserved because `nh os switch` reasserts the Nix-rendered file. |
| `extraComponents` short list | Module auto-parses `config` for deps now (`autoExtraComponents` removed). Listing `homekit`, `backup`, `met`, `default_config` covers anything not strictly inferred. Harmless if redundant. |
| Symlinks via `tmpfiles` (not `etc.* `) | `!include` resolves paths relative to `configDir`, not nix store. `tmpfiles` is the simplest stable bridge. |
| Backup runs as `hass` (not root) | `/var/backups/hass` is on root ext4, owned `hass:hass`. No NTFS/uid problem. No privilege escalation. |
| Online SQLite `.backup` (not raw tar of live DB) | Live tar can capture a torn WAL state. `.backup` is the SQLite-supported atomic snapshot path. Also dodges HA core issue #148156 (HA-native backups break on NixOS due to symlink resolution). |
| Backup at 03:30 + `Persistent` + jitter | Quiet hour; missed runs catch up at next boot; jitter avoids dogpile. |
| Firewall only opens 21063 + 5353 | HomeKit Bridge is L2 LAN only. mDNS is HA's responder, not avahi (avoid dueling responders). |
| `services.avahi` left disabled | HA ships its own zeroconf — running avahi too creates conflicting mDNS responses. |

### HomeKit Bridge config file

```yaml
# modules/nixos/home-assistant/packages/homekit-bridge.yaml
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
    # Start permissive; tighten with include_entities once HA discovers devices.
```

### `secrets.yaml` (seeded manually, not in git)

```yaml
# /var/lib/hass-secrets/secrets.yaml — chmod 0600 hass:hass
homekit_pin: "031-45-154"   # Apple pairing format. Pick any 8-digit value, write it down.
```

## First-run procedure

1. **Seed secrets on endeavour**:

   ```bash
   ssh endeavour
   sudo install -d -o hass -g hass -m 0750 /var/lib/hass-secrets
   sudo $EDITOR /var/lib/hass-secrets/secrets.yaml
   sudo chown hass:hass /var/lib/hass-secrets/secrets.yaml
   sudo chmod 0600 /var/lib/hass-secrets/secrets.yaml
   ```

   Stash the PIN in 1Password (entry: "Home Assistant — HomeKit Bridge").

2. **Cloudflare DNS** (from any host with `flarectl` available):

   ```bash
   flarectl dns create --zone garrisonsbygrace.com --name hass --type A --content 100.118.65.11 --ttl 1
   ```

3. **Build + test**:

   ```bash
   nh os build . --no-nom
   nh os test  . --no-nom
   ```

4. **Onboarding over local loopback (NOT the public hostname)** — guards against the "onboarding race" where an unprotected wizard sits on a public URL:

   ```bash
   ssh -L 8123:127.0.0.1:8123 endeavour
   # browser → http://localhost:8123
   ```

   Create the owner account, set location, decline analytics if desired.

5. **Verify HTTPS path**:

   ```bash
   curl -I https://hass.garrisonsbygrace.com
   ```

   Expect a 200 from HA with a valid cert. If you get 400, `trusted_proxies` is wrong. If cert is missing, check `journalctl -u acme-hass.garrisonsbygrace.com.service`.

6. **Pair HomeKit Bridge**:
   On iPhone → Home app → Add Accessory → "More options" → "GarrisonsByGrace Bridge" appears via mDNS → enter PIN from `secrets.yaml`. Devices then propagate to HomePods automatically.

7. **Commit the build**:

   ```bash
   nh os switch . --no-nom
   ```

8. **Backup smoke**:

   ```bash
   sudo systemctl start hass-backup.service
   sudo systemctl status hass-backup.service
   ls -lh /var/backups/hass/
   systemctl list-timers hass-backup.timer
   ```

## Operations

### Routine commands

```bash
# Service health
systemctl status home-assistant
journalctl -u home-assistant -f

# Backup unit
systemctl status hass-backup.timer
systemctl status hass-backup.service
journalctl -u hass-backup -n 50
ls -lh /var/backups/hass/

# Reach HA web UI
# - https://hass.garrisonsbygrace.com   (Tailscale-reachable, the only network path)
# - http://127.0.0.1:8123               (on endeavour itself, or via `ssh -L`)
```

### Manual restore drill

```bash
sudo systemctl stop home-assistant
sudo mv /var/lib/hass /var/lib/hass.broken-$(date +%s)
sudo install -d -o hass -g hass /var/lib/hass
sudo tar -I 'zstd -d' -xf /var/backups/hass/hass-<stamp>.tar.zst -C /var/lib/hass
sudo chown -R hass:hass /var/lib/hass
sudo systemctl start home-assistant
```

### Failure / rollback

- `nh os test` failure: reboot, last-known-good generation resumes.
- `nh os switch` lands broken: pick previous generation at boot, or `sudo nixos-rebuild switch --rollback`.
- `.storage/` corruption: restore latest archive per the drill above.

## Open footguns (documented, not fixed in MVP)

- **HomePods on a different VLAN from endeavour**: mDNS won't cross subnets. Needs router-level mDNS reflector. Not a concern as long as endeavour and HomePods share a flat LAN.
- **HA version churn**: `nixpkgs-unstable` bumps HA near-weekly. If a custom component lags, pin HA via overlay (use `stable-overlay.nix` or pin a specific commit). Not done in MVP.
- **`/var/backups/hass` is on a single endeavour disk**: no off-host replication. A separate spec can add `rsync hass@endeavour:/var/backups/hass/ → <nas>` or push to B2/S3.
- **Future USB radios** (Z-Wave / Thread): the `hass` user is not in `dialout`. When the time comes, add `users.users.hass.extraGroups = [ "dialout" ];` and reference sticks via `/dev/serial/by-id/*` paths, not `/dev/ttyUSB0`. Some systemd hardening directives in the HA unit may also need relaxing for raw USB.
- **Recorder DB growth**: monitor `/var/lib/hass/home-assistant_v2.db` size. If it crosses ~2 GB, time to either tune `recorder.exclude:` filters or migrate to postgres (already on endeavour).

## Acceptance criteria

- [ ] `nh os build .` succeeds with the new module wired into the endeavour configuration.
- [ ] `nh os test .` brings up `home-assistant.service` cleanly (`systemctl status` is `active (running)`).
- [ ] `curl -I https://hass.garrisonsbygrace.com` returns `HTTP/2 200` with a valid cert.
- [ ] HA onboarding completes via Tailscale loopback; owner account exists.
- [ ] HomeKit Bridge appears in iPhone Home app's "Add Accessory" flow; pairing with the configured PIN succeeds.
- [ ] At least one HA-controlled entity (e.g., a `template` light or test switch) is visible in Apple Home via the bridge.
- [ ] `systemctl start hass-backup.service` produces a `hass-*.tar.zst` in `/var/backups/hass/` of reasonable size (>1 MB).
- [ ] `systemctl list-timers hass-backup.timer` shows next run within 24h.
- [ ] Module file location, naming, and style match existing services (forgejo, jellyfin, searx).
- [ ] No new secrets in git history.

## Followup specs queued

1. Thread/Matter Border Router (when 802.15.4 stick arrives — Silicon Labs or Nordic).
2. ESPHome service (ESP32/8266 firmware build + serve).
3. MQTT broker (mosquitto) + integration patterns.
4. Off-host backup replication.
5. Postgres recorder migration (only if DB growth forces it).
