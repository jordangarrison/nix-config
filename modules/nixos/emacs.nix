{ config, lib, pkgs, ... }:

{
  services.emacs = { enable = true; };
  environment.systemPackages = with pkgs;
    if stdenv.isLinux then [ wl-clipboard xclip ] else [ ];
}
