{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.braveApps;

  # Generate desktop entries
  apps = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        userDataDir = "${config.home.homeDirectory}/.local/share/brave-apps/${appId}";
        # Use app name as icon name if a custom icon path is provided
        iconName =
          if (builtins.typeOf app.icon == "path")
          then appId
          else app.icon;
        # Extract hostname from URL for WM_CLASS
        # Brave uses pattern: brave-{hostname}__-Default
        urlMatch = builtins.match "https?://([^/]+).*" app.url;
        hostname = if urlMatch != null then builtins.head urlMatch else app.name;
        wmClass = "brave-${hostname}__-Default";
      in
      nameValuePair appId {
        name = app.name;
        exec = "${pkgs.brave}/bin/brave --app=${app.url} --user-data-dir=${userDataDir} --class=${app.name} --name=${app.name}";
        icon = iconName;
        type = "Application";
        categories = app.categories;
        comment = "${app.name} Web App";
        settings = {
          StartupWMClass = wmClass;
        };
      }
    )
    cfg.apps);

  # Generate icon files for apps that have custom icon paths
  iconFiles = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
      in
      nameValuePair ".local/share/icons/hicolor/scalable/apps/${appId}.png" {
        source = app.icon;
      }
    )
    (filter (app: builtins.typeOf app.icon == "path") cfg.apps));
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
        icon = mkOption {
          type = types.either types.str types.path;
          default = "brave";
          description = "Icon name or path for the desktop entry.";
        };
      };
    });
    default = [ ];
    description = "List of Chromium web apps to create.";
  };

  config = {
    xdg.desktopEntries = apps;
    home.file = iconFiles;
  };
}
