{ config, pkgs, lib, ... }:

with lib;

{
  options.gbg-config.gnome-tweaks.machine-type = mkOption {
    type = types.enum [ "laptop" "desktop" ];
    default = "desktop";
    description = "The type of machine this is.";
  };

  config = {
    # If the machine is a desktop, disable suspend
    systemd.sleep = mkIf (config.gbg-config.gnome-tweaks.machine-type == "desktop") {
      extraConfig = ''
        AllowSuspend=no
        AllowHibernation=no
        AllowHybridSleep=no
        AllowSuspendThenHibernate=no
      '';
    };

    # Enable the X11 windowing system
    services.xserver = {
      enable = true;

      # Configure keymap in X11
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    # Enable the GNOME Desktop Environment
    services.desktopManager.gnome.enable = true;

    # Enable the GDM display manager
    services.displayManager.gdm = {
      enable = true;
      autoSuspend = config.gbg-config.gnome-tweaks.machine-type == "laptop";
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

      # Common desktop applications
      # Can be overridden in individual configs as needed
    ];
  };
}
