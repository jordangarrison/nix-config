{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

with lib;

{
  config = {
    # If the machine is a desktop, disable suspend
    # Uses gbg-config.machine.type from common.nix
    systemd.sleep = mkIf (config.gbg-config.machine.type == "desktop") {
      settings.Sleep = {
        AllowSuspend = "no";
        AllowHibernation = "no";
        AllowHybridSleep = "no";
        AllowSuspendThenHibernate = "no";
      };
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
      autoSuspend = config.gbg-config.machine.type == "laptop";
    };

    # Enable GNOME services
    services.gnome.core-shell.enable = true;
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gnome-remote-desktop.enable = true;

    # GNOME desktop settings
    services.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.mutter]
      experimental-features=['scale-monitor-framebuffer']
    ''
    # Desktops/servers: also stop the GNOME session from *attempting* idle
    # suspend (schema default is 'suspend' after 15 min, even on AC). The
    # systemd.sleep block above already makes the verb fail, but without this
    # gsd-power retries a refused suspend every idle period.
    + optionalString (config.gbg-config.machine.type == "desktop") ''
      [org.gnome.settings-daemon.plugins.power]
      sleep-inactive-ac-type='nothing'
      sleep-inactive-battery-type='nothing'
    '';

    # The overrides package only compiles the core desktop schemas, so an
    # override targeting org.gnome.settings-daemon.* is silently dropped
    # unless the schema's owning package is listed here.
    services.desktopManager.gnome.extraGSettingsOverridePackages = [
      pkgs.gnome-settings-daemon
    ];

    # Enable D-Bus
    services.dbus.enable = true;

    # Install Firefox release and Nightly
    programs.firefox.enable = true;

    # 1Password programs
    programs._1password-gui.enable = true;
    programs._1password.enable = true;

    # Common GNOME packages
    environment.systemPackages = with pkgs; [
      inputs.firefox-nightly.packages.${pkgs.stdenv.hostPlatform.system}.firefox-nightly-bin

      # GNOME utilities
      gnome-tweaks
      gnome-remote-desktop
      gnome-session

      # Common desktop applications
      # Can be overridden in individual configs as needed
    ];
  };
}
