{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.ghosttyApps;

  # Create wrapper scripts for each app
  wrapperScripts = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        scriptName = "ghostty-${appId}";
        script = pkgs.writeShellScript scriptName ''
          exec ${pkgs.ghostty}/bin/ghostty --class="${app.name}" --title="${app.name}" -e ${escapeShellArg app.command}
        '';
      in
      nameValuePair appId script
    )
    cfg.apps);

  apps = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        iconName =
          if (builtins.typeOf app.icon == "path")
          then appId
          else app.icon;
        script = wrapperScripts.${appId};
      in
      nameValuePair appId {
        name = app.name;
        exec = "${script}";
        icon = iconName;
        type = "Application";
        categories = app.categories;
        comment = "${app.name} Ghostty Terminal App";
        settings = {
          StartupWMClass = app.name;
        };
      }
    )
    cfg.apps);
in
{
  options.ghosttyApps.apps = mkOption {
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
          type = types.either types.str types.path;
          default = "utilities-terminal";
          description = "Icon name for the desktop entry.";
        };
      };
    });
    default = [ ];
    description = "List of Ghostty terminal applications to create.";
  };

  config = {
    xdg.desktopEntries = apps;
  };
}
