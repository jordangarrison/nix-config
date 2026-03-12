{ config, lib, pkgs, ... }:

{
  services.lakeline-cg.enable = true;

  security.acme.certs."cg.garrisonsbygrace.com" = {
    group = "nginx";
  };

  services.nginx.virtualHosts."cg.garrisonsbygrace.com" = {
    forceSSL = true;
    useACMEHost = "cg.garrisonsbygrace.com";
    root = "${config.services.lakeline-cg.package}/share/lakeline-cg";
    locations."/" = {
      tryFiles = "$uri $uri/ /index.html =404";
    };
  };
}
