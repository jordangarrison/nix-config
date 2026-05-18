{ config, lib, pkgs, ... }:

let
  haPackages = pkgs.linkFarm "hass-packages" [
    { name = "homekit_bridge.yaml";
      path = ./home-assistant/packages/homekit_bridge.yaml; }
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

      # 2. tar everything else minus the live DB / WAL / SHM, then pull in
      #    the snapshot via a second -C directive in the same archive.
      tar --create \
          --file - \
          --exclude='home-assistant_v2.db' \
          --exclude='home-assistant_v2.db-wal' \
          --exclude='home-assistant_v2.db-shm' \
          --exclude='home-assistant.log*' \
          --exclude='deps' \
          -C /var/lib/hass . \
          -C "$work" home-assistant_v2.db \
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
    openFirewall    = false;             # nginx is the only ingress
    configWritable  = true;              # HA can edit configuration.yaml at runtime;
                                         # nh os switch reasserts the Nix-rendered version.
    extraComponents = [
      "default_config"
      "met"
      "backup"
      "google_translate"     # default_config auto-loads this; needs gtts dep
      "homekit"              # HomeKit Bridge: HA -> Apple Home
      # Apple-ecosystem deps: HomePods / Apple TVs on the LAN trigger zeroconf
      # discovery flows. Without these, HA logs ERRORs every scan even though
      # the integrations aren't configured. Pulling them in keeps logs clean
      # and lets us configure them via UI when ready.
      "apple_tv"
      "homekit_controller"   # adopt existing HomeKit devices into HA
      "thread"               # Thread integration shell (Border Router hardware deferred)
      "brother"              # Brother printer (matches the OS-level printer module)
      "ipp"                  # Internet Printing Protocol — companion to brother
    ];
    config = {
      homeassistant = {
        name         = "GarrisonsByGrace Home";
        time_zone    = config.time.timeZone;
        unit_system  = "us_customary";
        internal_url = "https://hass.garrisonsbygrace.com";
        external_url = "https://hass.garrisonsbygrace.com";
        # Split-config: HomeKit Bridge + future hand-authored YAML lives in
        # /var/lib/hass/packages/ (tmpfiles symlink below to a nix-store linkFarm).
        # HA never writes here, so a read-only store path is safe.
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
