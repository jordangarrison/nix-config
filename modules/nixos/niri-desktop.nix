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

  # XDG portal is handled by niri-flake (uses xdg-desktop-portal-gnome)
}
