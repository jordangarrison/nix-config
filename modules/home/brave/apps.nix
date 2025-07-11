{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.braveApps;

  apps = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        userDataDir = "${config.home.homeDirectory}/.local/share/brave-apps/${appId}";
      in
      nameValuePair appId {
        name = app.name;
        exec = "${pkgs.brave}/bin/brave --app=${app.url} --user-data-dir=${userDataDir} --class=${app.name} --name=${app.name}";
        icon = "brave";
        type = "Application";
        categories = app.categories;
        comment = "${app.name} Web App";
        settings = {
          StartupWMClass = app.name;
        };
      }
    )
    cfg.apps);
in
{
  options.braveApps.apps = mkOption {
    type = types.listOf (types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Display name of the web app.";
        };
        url = mkOption {
          type = types.str;
          description = "URL of the web app.";
        };
        categories = mkOption {
          type = types.listOf types.str;
          default = [ "Network" ];
          description = "Desktop categories for the web app.";
        };
      };
    });
    default = [ ];
    description = "List of Chromium web apps to create.";
  };

  config = {
    xdg.desktopEntries = apps;
  };
}
