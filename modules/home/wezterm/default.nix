{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.weztermApps;

  # Create wrapper scripts for each app
  wrapperScripts = listToAttrs (map
    (app:
      let
        appId = toLower (replaceStrings [ " " ] [ "-" ] app.name);
        scriptName = "wezterm-${appId}";
        script = pkgs.writeShellScript scriptName (
          if app.sshHost != null then
            # SSH mode: wezterm ssh host [-- command]
            if app.command != null then
              ''exec ${pkgs.wezterm}/bin/wezterm ssh ${app.sshHost} -- ${app.command}''
            else
              ''exec ${pkgs.wezterm}/bin/wezterm ssh ${app.sshHost}''
          else
            # Regular mode: wezterm start --class "X" -- sh -c command
            ''exec ${pkgs.wezterm}/bin/wezterm start --class "${app.name}" -- sh -c ${escapeShellArg app.command}''
        );
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
        comment = "${app.name} Terminal App";
        settings = {
          StartupWMClass = app.name;
        };
      }
    )
    cfg.apps);
in
{
  options.weztermApps.apps = mkOption {
    type = types.listOf (types.submodule {
      options = {
        name = mkOption {
          type = types.str;
          description = "Display name of the terminal app.";
        };
        command = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Command to run in the terminal. Required for regular apps, optional for SSH.";
        };
        sshHost = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "SSH host to connect to. When set, uses 'wezterm ssh' instead of regular start.";
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
    description = "List of terminal applications to create.";
  };

  config = {
    xdg.desktopEntries = apps;
  };
}
