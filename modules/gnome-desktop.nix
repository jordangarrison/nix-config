{ config, pkgs, ... }:

{
  # GUI
  services.xserver = {
    enable = true;
    displayManager = {
      gdm = {
        enable = true;
        # prevent autosuspend when no user is logged in
        autoSuspend = false;
      };
    };
    # Enable the GNOME Desktop Environment.
    desktopManager.gnome.enable = true;
  };
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gnome-remote-desktop.enable = true;

  environment.systemPackages = with pkgs; [
    gnome.gnome-tweaks
    gnome.gnome-remote-desktop
    gnome3.gnome-settings-daemon
    gnomeExtensions.appindicator
    gnomeExtensions.sound-output-device-chooser
    gnomeExtensions.clipboard-indicator
    gnomeExtensions.system-monitor
  ];
}
