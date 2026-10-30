{ config, lib, pkgs, ... }:

# Collie (https://github.com/AltanS/collie): phone web UI for the herdr agents
# on this box. It is remote shell access by design: a paired device can read
# every pane and type into it as jordangarrison. Three layers keep it private:
#   1. DNS: collie.jordangarrison.dev is an A record to the Tailscale IP.
#   2. nginx: only localhost and the Tailscale range get through. endeavour's
#      host firewall is off and nginx routes by Host, so without this a LAN
#      device could reach Collie with a spoofed Host header.
#   3. Collie: every API request needs a device token from `collie pair`.
# Collie's Tailscale-identity gate (trusted_user) needs `tailscale serve` in
# front, so it does not apply here; pairing is the auth.

let
  user = "jordangarrison";
  home = "/home/${user}";
  port = 8787;
  host = "collie.jordangarrison.dev";
  package = pkgs.callPackage ../../packages/collie { };
  root = "${package}/lib/collie";

  # Collie's machine-level config layer. The service and interactive verbs
  # (`collie pair`, `collie devices`) both read it via COLLIE_CONFIG, so the
  # pairing QR and `collie url` name the same front door the bridge serves.
  # This is the lowest file layer: ~/.config/collie/config.toml and .env both
  # win over it. Keep .env to secrets (push VAPID keys) and don't create that
  # config.toml, or they can silently replace the pinned hosts and origins.
  configFile = (pkgs.formats.toml { }).generate "collie-config.toml" {
    network = {
      host = "127.0.0.1";
      inherit port;
      public_hosts = [ host ];
      allowed_origins = [ "https://${host}" ];
      public_url = "https://${host}";
    };
    # nginx owns the front door; Collie must not run `tailscale serve`.
    serve.skip_serve = true;
  };

  # Shared by the service and the interactive CLI. Without HERDR_PLUGIN_CONFIG_DIR
  # the CLI asks `herdr plugin config-dir`, so `collie push-keys` would write an
  # .env under ~/.config/herdr/plugins/config that the service never reads.
  collieEnv = {
    COLLIE_CONFIG = "/etc/collie/config.toml";
    HERDR_PLUGIN_CONFIG_DIR = "${home}/.config/collie";
  };

  # The CLI on PATH, pointed at the same config as the service. A wrapper
  # rather than session variables so it also works in shells opened before a
  # switch. It execs the real binary by path, so Collie still resolves its
  # install root from it.
  cli = pkgs.writeShellScriptBin "collie" ''
    ${lib.toShellVars collieEnv}
    export ${lib.concatStringsSep " " (lib.attrNames collieEnv)}
    exec ${root}/bin/collie "$@"
  '';
in
{
  environment.etc."collie/config.toml".source = configFile;
  environment.systemPackages = [ cli ];

  # `collie push-keys` writes its .env here but won't create the directory.
  systemd.tmpfiles.rules = [ "d ${home}/.config/collie 0700 ${user} users - -" ];

  # A system unit running as the user, like agentsview: it reads the user's
  # herdr socket and agent logs, but runs without a login session.
  systemd.services.collie = {
    description = "Collie - phone web UI for herdr";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    restartTriggers = [ configFile ];

    # git: the Changes view. herdr: the multiplexer CLI. The per-user profile
    # holds the agent CLIs (pi, claude, codex): Collie runs
    # `<agent> --version` to trust an agent's input profile, and without it
    # sends into a running agent are held instead of queued.
    path = [
      pkgs.llm-agents.herdr
      pkgs.git
      pkgs.coreutils
      "/etc/profiles/per-user/${user}"
    ];

    environment = collieEnv // {
      HOME = home;
      COLLIE_PLUGIN_ROOT = root;
      HERDR_SOCKET_PATH = "${home}/.config/herdr/herdr.sock";
    };

    serviceConfig = {
      User = user;
      Group = "users";
      WorkingDirectory = root;
      ExecStart = "${lib.getExe package} _exec-bridge";
      EnvironmentFile = "-${home}/.config/collie/.env";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
    };
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
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow 100.64.0.0/10;
        deny all;
        # Collie accepts 10 MB attachments; leave room for multipart framing.
        client_max_body_size 12m;
        add_header X-Robots-Tag "noindex, nofollow" always;
      '';
    };
  };
}
