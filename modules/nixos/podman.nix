{ config, pkgs, lib, ... }:

{
  virtualisation.podman = {
    enable = true;
    # dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.systemPackages = with pkgs; [ buildah podman-compose podman-tui ];
}
