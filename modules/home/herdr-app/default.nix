{
  config,
  lib,
  pkgs,
  inputs,
  userApps ? { },
  ...
}:

let
  installHerdrT3 = pkgs.writeShellApplication {
    name = "install-herdr-t3";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      jq
      rsync
    ];
    text = builtins.readFile ./install-herdr-t3.sh;
  };
in
{
  config = lib.mkIf (userApps.herdr-app.enable or false) {
    home.packages = [ pkgs.llm-agents.herdr-app ];

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
      "herdr-app/mods/work-agents/mod.json".source = ./mods/work-agents/mod.json;
      "herdr-app/mods/work-agents/main.js".source = ./mods/work-agents/main.js;
      "herdr-app/mods/subscription-usage/mod.json".source = ./mods/subscription-usage/mod.json;
      "herdr-app/mods/subscription-usage/main.js".source = ./mods/subscription-usage/main.js;
      # From github:atuinsh/herdr-atuin-threads@6e2786d. Needs atuin threads;
      # see programs.atuin in users/jordangarrison/home.nix.
      "herdr-app/mods/atuin-threads/mod.json".source = ./mods/atuin-threads/mod.json;
      "herdr-app/mods/atuin-threads/main.js".source = ./mods/atuin-threads/main.js;
      "herdr-app/mods/atuin-threads/threads.svg".source = ./mods/atuin-threads/threads.svg;
      # Space folders (inputs.herdr-space-folders; `nix flake update
      # herdr-space-folders` to update). Herdr's main layout with a spaces
      # list that has folders. The mod keeps its folders in
      # ~/.config/herdr-space-folders.json; we do not manage that file. Its
      # next/prev space keys are the layout:main-folders section of keys.json.
      "herdr-app/layouts/main-folders.json".source =
        "${inputs.herdr-space-folders}/layouts/main-folders.json";
      "herdr-app/mods/space-folders/mod.json".source =
        "${inputs.herdr-space-folders}/mods/space-folders/mod.json";
      "herdr-app/mods/space-folders/main.js".source =
        "${inputs.herdr-space-folders}/mods/space-folders/main.js";
      # Issues panel (inputs.herdr-issues; `nix flake update herdr-issues` to
      # update). GitHub issues of the focused terminal's repo, beside Files and
      # Changes. Runs gh, curl and `hc read`; caches issues, avatars and
      # images in ~/.config/herdr-app/data/issues/, which we do not manage.
      # main-issues is Herdr's main layout with the panel and its button.
      "herdr-app/layouts/main-issues.json".source = "${inputs.herdr-issues}/layouts/main-issues.json";
      "herdr-app/mods/issues/mod.json".source = "${inputs.herdr-issues}/mods/issues/mod.json";
      "herdr-app/mods/issues/main.js".source = "${inputs.herdr-issues}/mods/issues/main.js";
      "herdr-app/mods/issues/viewer.js".source = "${inputs.herdr-issues}/mods/issues/viewer.js";
      "herdr-app/mods/issues/icons.js".source = "${inputs.herdr-issues}/mods/issues/icons.js";
      "herdr-app/mods/issues/pictures.js".source = "${inputs.herdr-issues}/mods/issues/pictures.js";
    };

    # Herdr T3 layout (inputs.herdr-t3; `nix flake update herdr-t3` to update).
    # Copied, not linked: see install-herdr-t3.sh. This step owns the t3-*
    # mods and layouts/herdr-t3.*; local edits to them are replaced.
    home.activation.herdrT3 = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe installHerdrT3} ${inputs.herdr-t3} "${config.xdg.configHome}/herdr-app"
    '';
  };
}
