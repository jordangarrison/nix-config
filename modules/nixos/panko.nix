{ config, lib, pkgs, ... }:

{
  services.panko = {
    enable = true;
    host = "panko.jordangarrison.dev";
    port = 4001;
    listenAddress = "127.0.0.1";
    secretKeyBaseFile = "/var/lib/panko/secrets/secret-key-base";
    tokenSigningSecretFile = "/var/lib/panko/secrets/token-signing-secret";
    database.createLocally = true;
    sessionWatchPaths = [
      "/home/jordangarrison/.claude/projects"
    ];
  };

  # Run as jordangarrison so the session watcher can read JSONL files
  # from ~/.claude/projects and inotifywait resolves correctly.
  # NOTE: This weakens upstream systemd hardening (ProtectHome=false).
  # Long-term, consider syncing JSONL files to /var/lib/panko/sessions/ instead.
  systemd.services.panko.serviceConfig = {
    User = lib.mkForce "jordangarrison";
    Group = lib.mkForce "users";
    ProtectHome = lib.mkForce false;
  };

  # FileSystem library needs inotifywait at runtime for file watching
  systemd.services.panko.path = [ pkgs.inotify-tools ];

  # Override PHX_SCHEME and PHX_URL_PORT since nginx is configured externally
  # (services.panko.nginx.enable is false), so the upstream module defaults
  # to http/4001 instead of https/443.
  systemd.services.panko.environment = {
    PHX_SCHEME = lib.mkForce "https";
    PHX_URL_PORT = lib.mkForce "443";
  };

  # ACME certificate via Cloudflare DNS-01 (defaults from nginx.nix)
  security.acme.certs."panko.jordangarrison.dev" = {
    group = "nginx";
  };

  # Nginx reverse proxy
  services.nginx.virtualHosts."panko.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "panko.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://localhost:${toString config.services.panko.port}";
      proxyWebsockets = true;
    };
  };
}
