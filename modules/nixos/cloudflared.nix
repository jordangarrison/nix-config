{ config, lib, pkgs, ... }:

{
  services.cloudflared = {
    enable = true;
    tunnels."71e2092b-5e07-4125-8329-f538bdc58d48" = {
      credentialsFile = "/var/lib/cloudflared/panko.json";
      default = "http_status:404";
      ingress = {
        "panko.jordangarrison.dev" = "http://localhost:4001";
      };
    };
  };
}
