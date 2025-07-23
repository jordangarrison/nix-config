{ config, lib, pkgs, ... }:

{
  fonts = {
    enableDefaultPackages = true;
    packages = [ pkgs.nerd-fonts.fira-code ];
  };
}
