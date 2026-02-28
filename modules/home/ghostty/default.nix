{ lib, pkgs, ... }:

let
  commonConfig = ''
    # Font
    font-family = Source Code Pro
    font-size = 10

    # Window
    background-opacity = 0.80
    window-padding-x = 5
    window-padding-y = 5

    # Theme (built-in rose-pine)
    theme = Rose Pine

    # Shell integration
    shell-integration = zsh

    # Keybindings
    # Shift+Enter sends newline for Claude Code multiline input
    keybind = shift+enter=text:\n
  '';
in
lib.mkMerge [
  (lib.mkIf pkgs.stdenv.isLinux {
    # NixOS class: tiling WM manages decorations
    home.file.".config/ghostty/config".text = commonConfig + ''
      # Linux/NixOS: tiling WM manages decorations
      window-decoration = none
      gtk-titlebar = false
    '';
  })
  (lib.mkIf pkgs.stdenv.isDarwin {
    # Darwin class: native tab bar
    home.file.".config/ghostty/config".text = commonConfig + ''
      # macOS/Darwin: native tab bar
      window-decoration = auto
      macos-titlebar-style = tabs
    '';
  })
]
