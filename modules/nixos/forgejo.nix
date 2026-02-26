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
        HTTP_ADDR = "0.0.0.0";
        HTTP_PORT = 7770;
        DOMAIN = "endeavour.owl-yo.ts.net";
        ROOT_URL = "http://endeavour.owl-yo.ts.net:7770/";
        SSH_DOMAIN = "endeavour.owl-yo.ts.net";
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

  # Open the web UI port for Tailscale access
  networking.firewall.allowedTCPPorts = [ 7770 ];
}
