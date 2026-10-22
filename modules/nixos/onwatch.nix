{ config, lib, pkgs, inputs, ... }:

let
  user = "jordangarrison";
  home = "/home/${user}";
  dataDir = "${home}/.onwatch";
  port = 9211;
  host = "onwatch.jordangarrison.dev";
  onwatch = inputs.onwatch.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # Runs as the user so onwatch auto-detects provider credentials
  # (~/.claude/.credentials.json, ~/.codex/auth.json, ...). Admin login and
  # provider API keys live in ~/.onwatch/.env (written by `onwatch setup`);
  # onwatch loads it itself, and the variables set here take precedence.
  # Don't run `onwatch start` on this host: it stops whatever holds the port.
  systemd.services.onwatch = {
    description = "onWatch - AI API quota tracker";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      HOME = home;
      ONWATCH_HOST = "127.0.0.1";
      ONWATCH_PORT = toString port;
      ONWATCH_DB_PATH = "${dataDir}/data/onwatch.db";
      ONWATCH_SECURE_COOKIES = "true";
      # No desktop session for a system service; the tray runs as the
      # onwatch-menubar user service below.
      ONWATCH_DISABLE_TRAY = "1";
    };

    serviceConfig = {
      User = user;
      Group = "users";
      # Foreground, logging to the journal.
      ExecStart = "${onwatch}/bin/onwatch --debugstdout";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Tray companion in the desktop session. It reads the daemon's dashboard on
  # localhost and its menubar settings from the same database, and exits ~30s
  # after the daemon disappears, hence Restart=always.
  home-manager.users.${user}.systemd.user.services.onwatch-menubar = {
    Unit = {
      Description = "onWatch tray companion";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Environment = [ "ONWATCH_DB_PATH=${dataDir}/data/onwatch.db" ];
      ExecStart = "${onwatch}/bin/onwatch menubar --port ${toString port}";
      Restart = "always";
      RestartSec = "10s";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  security.acme.certs.${host} = {
    group = "nginx";
    # The system resolver (Tailscale -> blocky) caches the challenge record's
    # NXDOMAIN, so lego's propagation check times out. Check via Cloudflare.
    dnsResolver = "1.1.1.1:53";
  };

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    useACMEHost = host;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
    };
  };
}
