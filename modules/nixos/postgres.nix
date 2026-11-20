{ config, lib, pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "metabase" ];
    ensureUsers = [
      {
        name = "metabase";
        ensureDBOwnership = true;
      }
    ];
    # Local clients only: every user of this server (Panko, Norish, local dev
    # databases) connects over the socket or 127.0.0.1. "false" means
    # listen_addresses = "localhost"; the unix socket stays.
    enableTCPIP = false;
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser      origin                  auth-method
      local all       all                                 trust

      # Allow connections from localhost
      host  all       all         127.0.0.1/32            trust
      host  all       all         ::1/128                 trust
    '';
  };
  services.prometheus.exporters.postgres = {
    enable = true;
    # Nothing scrapes it from another host.
    listenAddress = "127.0.0.1";
    port = 9187;
  };

}
