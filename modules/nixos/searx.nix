{ config, lib, pkgs, ... }:

{
  services.searx = {
    enable = true;
    redisCreateLocally = true;
    settings = {
      server = {
        bind_address = "0.0.0.0";
        # port = yourPort;
        # WARNING: setting secret_key here might expose it to the nix cache
        # see below for the sops or environment file instructions to prevent this
        secret_key = "garrisonsbygrace"; # Running locally not worried about it
      };
      outgoing = {
        pool_connections = 100;
        pool_maxsize = 200;
        max_connections = 200;
      };
      general = {
        timeout = 2.0; # default is 4
      };
    };
  };
}
