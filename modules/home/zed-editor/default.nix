{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  homeDirectory = config.home.homeDirectory;
  configsPath = "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/configs";
in {
  # Zed editor with Doom-style keybindings
  programs.zed-editor = {
    enable = true;

    # Extensions managed via nix-zed-extensions overlay
    # Note: These are initial extensions; Zed downloads them on first launch
    extensions = [
      "nix"
      "toml"
      "html"
      "dockerfile"
      "git-firefly"
    ];
  };

  # Symlink config files from repo for live editing with language server support
  xdg.configFile = {
    "zed/settings.json".source =
      config.lib.file.mkOutOfStoreSymlink "${configsPath}/zed/settings.json";

    "zed/keymap.json".source =
      config.lib.file.mkOutOfStoreSymlink "${configsPath}/zed/keymap.json";
  };
}
