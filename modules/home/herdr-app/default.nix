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
    # The work-items layout and mod are ours. Do not manage layouts/.state,
    # shared.json, or the app-generated guide, types, shipped layouts and
    # mods: Herdr owns and writes those files. Link only our files so the
    # app can still write jsconfig.json and .d.ts beside the mod.
    xdg.configFile = {
      "herdr-app/keys.json".source = ./keys.json;
      "herdr-app/settings.json".source = ./settings.json;
      "herdr-app/themes/rose-pine.json".source = ./rose-pine.json;
      "herdr-app/layouts/work-items.json".source = ./layouts/work-items.json;
      "herdr-app/layouts/work-items.svg".source = ./layouts/work-items.svg;
      "herdr-app/mods/work-items/mod.json".source = ./mods/work-items/mod.json;
      "herdr-app/mods/work-items/main.js".source = ./mods/work-items/main.js;
    };
  };
}
