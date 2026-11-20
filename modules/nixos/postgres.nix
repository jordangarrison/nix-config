{ config, lib, pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
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
    listenAddress = "0.0.0.0";
    port = 9187;
  };

}
