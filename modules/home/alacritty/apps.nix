{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.alacrittyApps;

  apps = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
      in
      nameValuePair appId {
        name = app.name;
        exec = "${pkgs.alacritty}/bin/alacritty --class ${app.name} --title \"${app.name}\" --command ${app.command}";
        icon = app.icon or "utilities-terminal";
        type = "Application";
        categories = app.categories;
        comment = "${app.name} Terminal App";
        settings = {
          StartupWMClass = app.name;
        };
      }
    )
    cfg.apps);
in
{
  options.alacrittyApps.apps = mkOption {
    type = types.listOf (types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Display name of the terminal app.";
        };
        command = mkOption {
          type = types.str;
          description = "Command to run in the terminal.";
        };
        categories = mkOption {
          type = types.listOf types.str;
          default = [ "System" ];
          description = "Desktop categories for the terminal app.";
        };
        icon = mkOption {
          type = types.str;
          default = "utilities-terminal";
          description = "Icon name for the desktop entry.";
        };
      };
    });
    default = [ ];
    description = "List of terminal applications to create.";
  };

  config = {
    xdg.desktopEntries = apps;
  };
}
