{ config, lib, pkgs, ... }:

let
  cfg = config.services.day-dashboard;
in
{
  # System-level *infrastructure* for the day dashboard: the served directory,
  # the secrets dir, and a private nginx vhost + ACME cert. The generator job
  # itself runs as a systemd **user** service (modules/home/day-dashboard),
  # because gathering data drives the Pi MCP servers and `gws`, both of which
  # read the user's unlocked login keyring — unavailable to a bare system unit.
  options.services.day-dashboard = {
    enable = lib.mkEnableOption "private nginx vhost + state dirs for the day dashboard";

    user = lib.mkOption {
      type = lib.types.str;
      default = "jordangarrison";
      description = "Owner of the state/output directories (matches the user service).";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/day-dashboard";
      description = "Base state dir; the vhost serves <stateDir>/www.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "day.jordangarrison.dev";
      description = ''
        Virtual host name. Keep this private: point its DNS A record at the
        Tailscale IP (100.118.65.11) so the vhost is only reachable inside the
        tailnet, and the access guard below further restricts it.
      '';
    };

    dismissPort = lib.mkOption {
      type = lib.types.port;
      default = 8846;
      description = "localhost port of the dismiss handler to proxy /dismiss to (match the home module).";
    };

    allowedRanges = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" "::1" "100.64.0.0/10" ];
      description = ''
        nginx allow list. Defaults to localhost + the Tailscale CGNAT range only
        — everything else is denied. RFC1918 LAN is deliberately excluded: the
        page aggregates private Slack/email/Linear data, nginx routes by Host
        header, and endeavour's host firewall is disabled, so allowing the LAN
        would let any LAN device reach it with a spoofed Host. Add a LAN range
        here only if you accept that exposure.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # State dirs are group-nginx and 0750: the aggregated Slack/email/Linear
    # data under here must not be readable by the other local accounts on this
    # box (family users). nginx (group nginx) can still traverse and read the
    # served www/ files; "other" cannot even enter the dir. secrets/ stays 0700.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} nginx - -"
      "d ${cfg.stateDir}/secrets 0700 ${cfg.user} ${cfg.user} - -"
      "d ${cfg.stateDir}/www 0750 ${cfg.user} nginx - -"
    ];

    security.acme.certs.${cfg.host} = {
      group = "nginx";
    };

    services.nginx.virtualHosts.${cfg.host} =
      let
        guard = ''
          ${lib.concatMapStringsSep "\n" (r: "allow ${r};") cfg.allowedRanges}
          deny all;
        '';
      in
      {
        forceSSL = true;
        useACMEHost = cfg.host;
        root = "${cfg.stateDir}/www";
        locations."/" = {
          index = "index.html";
          tryFiles = "$uri $uri/ =404";
          extraConfig = ''
            ${guard}
            add_header X-Robots-Tag "noindex, nofollow" always;
            add_header Cache-Control "no-store" always;
          '';
        };
        # ✕ dismiss links call the localhost handler, which records the
        # dismissal, re-renders instantly, and 302s back to "/".
        locations."~ ^/(dismiss|undismiss|dismissed)$" = {
          proxyPass = "http://127.0.0.1:${toString cfg.dismissPort}";
          extraConfig = guard;
        };
      };
  };
}
