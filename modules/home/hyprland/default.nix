{ config, pkgs, lib, osConfig ? null, ... }:

let
  homeDirectory = config.home.homeDirectory;
  hyprConfigPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/hypr";
  wallpapersPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/wallpapers";

  # Get hostname from osConfig if available (NixOS), otherwise use null
  hostname = if osConfig != null then osConfig.networking.hostName else null;
in
{
  # Import shared desktop tools (satty, screenshot tools, clipboard, etc.)
  imports = [ ../desktop-tools ];

  home.packages = with pkgs; [
    # Core Hyprland tools
    hyprpaper
    hyprlock
    hypridle
    hyprpicker

    # Status bar
    waybar

    # Notification daemon
    mako

    # Application launcher
    walker

    # Rofi launcher
    rofi

    # File manager (terminal)
    yazi

    # System tray applets
    networkmanagerapplet
    blueman

    # Authentication
    polkit_gnome

    # Logout menu
    wlogout
  ];

  # Disable mako systemd service - let desktop autostart handle it
  # This prevents conflicts when running multiple desktops (Hyprland/Niri)
  systemd.user.services.mako = {
    Install.WantedBy = lib.mkForce [ ];
  };

  # Yazi file manager configuration
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
  };

  # XDG config files via mkOutOfStoreSymlink for live editing
  xdg.configFile = {
    # Core Hyprland configs
    "hypr/hyprland.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/hyprland.conf";
    "hypr/theme.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/theme.conf";
    "hypr/keybinds.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/keybinds.conf";
    "hypr/rules.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/rules.conf";
    "hypr/autostart.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/autostart.conf";

    # Lock and idle
    "hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/hyprlock.conf";
    "hypr/hypridle.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/hypridle.conf";

    # Wallpaper
    "hypr/hyprpaper.conf".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/hyprpaper.conf";

    # Monitor configurations directory
    "hypr/monitors".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/monitors";

    # Host-specific monitor configuration symlink
    "hypr/monitors.conf".source = lib.mkIf (hostname != null)
      (config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/monitors/${hostname}.conf");

    # Waybar
    "waybar/config.jsonc".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/waybar/config.jsonc";
    "waybar/style.css".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/waybar/style.css";

    # Mako notifications
    "mako/config".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/mako/config";

    # Walker launcher
    "walker/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/walker/config.toml";

    # Rofi launcher
    "rofi/config.rasi".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/rofi/config.rasi";
    "rofi/theme.rasi".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/rofi/theme.rasi";
  };

  # Wallpapers directory symlink
  home.file."Pictures/Wallpapers/wallpaper.png".source = config.lib.file.mkOutOfStoreSymlink "${wallpapersPath}/wallpaper.png";

  # GTK/Qt theming for visual consistency
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      size = 24;
    };
  };

  # Qt theming
  qt = {
    enable = true;
    platformTheme.name = "adwaita";
    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  # Environment variables for cursor
  home.sessionVariables = {
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
  };
}
