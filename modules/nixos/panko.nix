{ config, lib, pkgs, ... }:

{
  services.panko = {
    enable = true;
    host = "panko.jordangarrison.dev";
    port = 4001;
    listenAddress = "0.0.0.0";
    secretKeyBaseFile = "/var/lib/panko/secrets/secret-key-base";
    tokenSigningSecretFile = "/var/lib/panko/secrets/token-signing-secret";
    database.createLocally = true;
    sessionWatchPaths = [
      "/home/jordangarrison/.claude/projects"
    ];
  };

  # Run as jordangarrison so the session watcher can read JSONL files
  # from ~/.claude/projects and inotifywait resolves correctly
  systemd.services.panko.serviceConfig = {
    User = lib.mkForce "jordangarrison";
    Group = lib.mkForce "users";
    ProtectHome = lib.mkForce false;
  };

  # FileSystem library needs inotifywait at runtime for file watching
  systemd.services.panko.path = [ pkgs.inotify-tools ];

  # ACME certificate via Cloudflare DNS-01 (defaults from nginx.nix)
  security.acme.certs."panko.jordangarrison.dev" = {
    group = "nginx";
  };

  # Nginx reverse proxy
  services.nginx.virtualHosts."panko.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "panko.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://localhost:4001";
      proxyWebsockets = true;
    };
  };
}
