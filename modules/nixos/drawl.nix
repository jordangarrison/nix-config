{ config, lib, pkgs, ... }:

let
  port = 5555;
in
{
  # Provide the drawl package via the upstream module options. nginx
  # integration in the upstream module is disabled — we serve the static
  # bundle ourselves on a local port and expose it publicly through the
  # existing Cloudflare tunnel (see cloudflared.nix).
  services.drawl = {
    enable = true;
    host = "drawl.jordangarrison.dev";
  };

  services.nginx.virtualHosts."drawl.jordangarrison.dev-local" = {
    serverName = "drawl.jordangarrison.dev";
    listen = [
      {
        addr = "127.0.0.1";
        port = port;
      }
    ];
    root = "${config.services.drawl.package}/share/drawl";
    locations."/" = {
      tryFiles = "$uri $uri/ /index.html =404";
    };
  };
}
