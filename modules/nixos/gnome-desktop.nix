{ config, pkgs, ... }:

{
  # Enable the X11 windowing system
  services.xserver = {
    enable = true;

    # Configure keymap in X11
    xkb = {
      layout = "us";
      variant = "";
    };

    # Enable the GNOME Desktop Environment
    desktopManager.gnome.enable = true;
  };

  # Enable the GDM display manager
  services.displayManager.gdm = {
    enable = true;
    autoSuspend = false;
  };

  # Enable GNOME services
  services.gnome.core-shell.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gnome-remote-desktop.enable = true;

  # GNOME desktop settings
  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.mutter]
    experimental-features=['scale-monitor-framebuffer']
  '';

  # Enable D-Bus
  services.dbus.enable = true;

  # Install Firefox
  programs.firefox.enable = true;

  # 1Password programs
  programs._1password-gui.enable = true;
  programs._1password.enable = true;

  # Common GNOME packages
  environment.systemPackages = with pkgs; [
    # GNOME utilities
    gnome-tweaks
    gnome-remote-desktop
    gnome-session
    gnomeExtensions.clipboard-history

    # Common desktop applications
    # Can be overridden in individual configs as needed
  ];
}
