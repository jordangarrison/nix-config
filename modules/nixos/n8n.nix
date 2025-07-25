{ config, lib, pkgs, ... }:

{
  services.n8n = {
    enable = true;
    openFirewall = true;
  };
}
