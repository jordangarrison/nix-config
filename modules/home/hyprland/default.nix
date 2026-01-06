{ config, pkgs, lib, ... }:

let
  homeDirectory = config.home.homeDirectory;
  hyprConfigPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs/hypr";
in
{
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
    libnotify

    # Application launcher
    walker

    # Screenshot tools
    grim
    slurp
    satty

    # Clipboard
    wl-clipboard
    cliphist

    # File manager (terminal)
    yazi

    # Utilities
    brightnessctl
    playerctl
    pamixer

    # System tray applets
    networkmanagerapplet
    blueman

    # Authentication
    polkit_gnome

    # Logout menu
    wlogout
  ];

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

    # Waybar
    "waybar/config.jsonc".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/waybar/config.jsonc";
    "waybar/style.css".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/waybar/style.css";

    # Mako notifications
    "mako/config".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/mako/config";

    # Satty screenshot tool
    "satty/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${hyprConfigPath}/satty/config.toml";
  };

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
