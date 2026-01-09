{ config, pkgs, lib, ... }:

let
  homeDirectory = config.home.homeDirectory;
  configPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs";
in {
  # Shared desktop tools for Wayland compositors (Hyprland, Niri, etc.)

  home.packages = with pkgs; [
    # Screenshot tools
    grim
    slurp
    satty

    # Clipboard
    wl-clipboard
    cliphist

    # Emoji picker
    rofimoji

    # Notifications (for notify-send compatibility)
    libnotify

    # Utilities
    brightnessctl
    playerctl
    pamixer
  ];

  # Ensure screenshots directory exists
  home.file."Pictures/Screenshots/.keep".text = "";

  # Shared config files (symlinked for live editing)
  xdg.configFile = {
    # Satty screenshot annotation tool
    "satty/config.toml".source =
      config.lib.file.mkOutOfStoreSymlink
        "${configPath}/satty/config.toml";
  };
}
