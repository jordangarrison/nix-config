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
      default = [ "127.0.0.1" "::1" "100.64.0.0/10" "192.168.0.0/16" ];
      description = ''
        nginx allow list. Defaults to localhost, the Tailscale CGNAT range and
        RFC1918 LAN. Everything else is denied — defense in depth on top of the
        tailnet-only DNS, since endeavour's host firewall is disabled.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # secrets/ holds the optional Confluence credential file (see the package
    # README). 0700 so only the service user can read it. www/ is the served
    # root and must be traversable by nginx; the user service writes into it.
    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0755 ${cfg.user} users - -"
      "d ${cfg.stateDir}/secrets 0700 ${cfg.user} users - -"
      "d ${cfg.stateDir}/www 0755 ${cfg.user} users - -"
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
