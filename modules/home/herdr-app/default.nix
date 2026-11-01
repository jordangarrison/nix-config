{
  lib,
  pkgs,
  inputs,
  userApps ? { },
  ...
}:

{
  config = lib.mkIf (userApps.herdr-app.enable or false) {
    # Only the desktop app comes from the temporary PR input. The Herdr TUI
    # and all other agent packages stay on the regular llm-agents input.
    home.packages = [
      inputs.herdr-app.packages.${pkgs.stdenv.hostPlatform.system}.herdr-app
    ];

    # Keep personal configuration declarative, as with herdr/config.toml.
    # Do not manage layouts/.state, shared.json, or the app-generated guide,
    # types, shipped layouts and mods: Herdr owns and writes those files.
    xdg.configFile = {
      "herdr-app/keys.json".source = ./keys.json;
      "herdr-app/settings.json".source = ./settings.json;
      "herdr-app/themes/rose-pine.json".source = ./rose-pine.json;
    };
  };
}
