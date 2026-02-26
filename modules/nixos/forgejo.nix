{ config, lib, pkgs, ... }:

{
  services.forgejo = {
    enable = true;

    # SQLite backend
    database.type = "sqlite3";

    # Git LFS support
    lfs.enable = true;

    # Automatic daily backups
    dump = {
      enable = true;
      type = "tar.zst";
    };

    settings = {
      server = {
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 7770;
        DOMAIN = "forgejo.jordangarrison.dev";
        ROOT_URL = "https://forgejo.jordangarrison.dev/";
        SSH_DOMAIN = "forgejo.jordangarrison.dev";
        # Use the host's openssh for SSH cloning
        START_SSH_SERVER = false;
        SSH_PORT = 22;
      };

      service = {
        DISABLE_REGISTRATION = true;
        DEFAULT_PRIVATE = "private";
      };
    };
  };

  security.acme.certs."forgejo.jordangarrison.dev" = {
    group = "nginx";
  };

  services.nginx.virtualHosts."forgejo.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "forgejo.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://localhost:7770";
    };
  };
}
