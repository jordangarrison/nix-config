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

  # The Niri session spawns polkit-gnome, which registers first, so niri-flake's
  # polkit-kde unit failed on every login until systemd stopped restarting it.
  systemd.user.services.niri-flake-polkit.enable = false;

  # Noctalia uses ddcutil for external-monitor brightness. This loads i2c-dev
  # and, through udev uaccess, gives whoever holds the active seat read/write
  # access to every /dev/i2c-* bus, not only the monitors' DDC channels. That
  # includes other local accounts on these hosts. Narrowing it to DDC buses
  # needs each host's GPU bus layout checked on hardware first.
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
