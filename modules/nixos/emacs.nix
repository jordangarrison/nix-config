{ config, lib, pkgs, ... }:

{
  services.emacs = {
    enable = true;
    package = if pkgs.stdenv.hostPlatform.isLinux then pkgs.emacs-pgtk else pkgs.emacs;
  };
  environment.systemPackages = with pkgs;
    if stdenv.hostPlatform.isLinux then [ wl-clipboard xclip ] else [ ];
}
