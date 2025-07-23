{ config, pkgs, ... }:

{
  imports = [ ./emacs.nix ];

  # Enable Docker
  virtualisation.docker.enable = true;
}
