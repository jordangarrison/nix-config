{ config, lib, pkgs, ... }:

{
  services.emacs = {
    enable = true;
    package = if pkgs.stdenv.isLinux then pkgs.emacs-pgtk else pkgs.emacs;
  };
  environment.systemPackages = with pkgs;
    if stdenv.isLinux then [ wl-clipboard xclip ] else [ ];
}
