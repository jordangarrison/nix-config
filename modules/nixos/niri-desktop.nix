{ config, lib, pkgs, inputs, ... }:

{
  # Import niri-flake NixOS module
  imports = [ inputs.niri.nixosModules.niri ];

  # Use the host nixpkgs package so its glibc can load the system Mesa
  # drivers from /run/opengl-driver. Keep niri-flake for configuration only.
  programs.niri = {
    enable = true;
    package = pkgs.niri;
  };

  # Noctalia uses ddcutil for external-monitor brightness. This loads i2c-dev
  # and grants local seat users access to /dev/i2c-* through udev.
  hardware.i2c.enable = true;

  # Essential system packages for niri
  environment.systemPackages = with pkgs; [
    xwayland-satellite # Xwayland support for X11 apps
    swaybg # Wallpaper
    swaylock # Lock screen
    swayidle # Idle management
  ];

  # niri-flake's default package uses the host pkgs; keep option docs from
  # evaluating that unused default against dependencies removed upstream.
  documentation.nixos.extraModules = [
    {
      options.programs.niri.package = lib.mkOption {
        defaultText = lib.literalExpression "(inputs.niri.lib.make-package-set pkgs).niri-stable";
      };
    }
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
