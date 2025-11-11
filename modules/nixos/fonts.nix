{ config, lib, pkgs, ... }:

{
  fonts = {
    packages = [
      pkgs.nerd-fonts.fira-code
      pkgs.noto-fonts-color-emoji
      pkgs.noto-fonts
    ];
  } // lib.optionalAttrs pkgs.stdenv.isLinux {
    enableDefaultPackages = true;
    fontconfig = {
      defaultFonts = {
        emoji = [ "Noto Color Emoji" ];
        monospace = [ "FiraCode Nerd Font" "Noto Color Emoji" ];
      };
    };
  };
}
