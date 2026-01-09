{ config, lib, pkgs, inputs, ... }:

{
  # Import niri-flake NixOS module
  imports = [ inputs.niri.nixosModules.niri ];

  # Apply niri overlay for package access
  nixpkgs.overlays = [ inputs.niri.overlays.niri ];

  # Enable niri compositor
  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };

  # Essential system packages for niri
  environment.systemPackages = with pkgs; [
    xwayland-satellite # Xwayland support for X11 apps
    swaybg # Wallpaper
    swaylock # Lock screen
    swayidle # Idle management
  ];

  # XDG portal configuration for screen sharing support
  # Based on niri's recommended niri-portals.conf
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      niri = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
      };
    };
  };
}
