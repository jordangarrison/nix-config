{ inputs, userApps, lib, ... }:

{
  imports = [ inputs.hex.homeManagerModules.hex ];

  programs.hex = lib.mkIf (userApps.hex.enable or false) {
    enable = true;
    autostart = true;
    # GNOME uses GlobalShortcuts; Niri also binds this directly in ../niri.
    # Handy keeps Super+Shift+D.
    shortcut = "control+option+space"; # Ctrl+Alt+Space on Linux
    settings.shortcut_mode = "toggle";
    model = "parakeet_v3";
    # Download explicitly as the desktop user, never during activation/build.
    installModel = false;
  };
}
