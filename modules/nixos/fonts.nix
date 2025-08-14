{ config, lib, pkgs, ... }:

{
  fonts = {
    packages = [ pkgs.nerd-fonts.fira-code ];
  } // lib.optionalAttrs pkgs.stdenv.isLinux {
    enableDefaultPackages = true;
  };
}
