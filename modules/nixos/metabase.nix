{ config, lib, pkgs, ... }:

{
  services.metabase = {
    enable = true;
    openFirewall = true;
    listen = {
      ip = "0.0.0.0";
      port = 5555;
    };
  };
}
