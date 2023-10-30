{ config, pkgs, ... }:

{
  # Enable Code Server
  services.code-server = {
    enable = true;
    user = "jordangarrison";
    group = "users";
    extraArguments = [ "--disable-telemetry" ];
    extraGroups = [ "docker" ];
    host = "0.0.0.0";
    auth = "none";
  };
}
