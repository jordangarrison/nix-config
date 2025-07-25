{ config, lib, pkgs, ... }:

{
  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Essential programs for Hyprland
  environment.systemPackages = with pkgs; [
    waybar
    wofi
    mako
    hyprpaper
    kitty
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
  ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config.common.default = "*";
  };
}
