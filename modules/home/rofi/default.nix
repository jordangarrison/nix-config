{ config, pkgs, lib, ... }:

let
  homeDirectory = config.home.homeDirectory;
  configPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs";
in {
  # Minimal rofi module for dmenu-style selection (keybinds help, etc.)

  home.packages = with pkgs; [
    rofi
  ];

  # Rofi configuration (symlinked for live editing)
  xdg.configFile = {
    "rofi/config.rasi".source =
      config.lib.file.mkOutOfStoreSymlink "${configPath}/rofi/config.rasi";
    "rofi/theme.rasi".source =
      config.lib.file.mkOutOfStoreSymlink "${configPath}/rofi/theme.rasi";
  };
}
