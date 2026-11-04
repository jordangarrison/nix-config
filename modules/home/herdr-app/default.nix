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

  installHerdrMods = pkgs.writeShellApplication {
    name = "install-herdr-mods";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      rsync
    ];
    text = builtins.readFile ./install-herdr-mods.sh;
  };

  # Third-party mods with more than one file: copied, not linked (see
  # install-herdr-mods.sh). Name in mods/ -> its folder in a flake input.
  copiedMods = {
    # Issues panel (inputs.herdr-issues; `nix flake update herdr-issues` to
    # update). GitHub issues of the focused terminal's repo, beside Files and
    # Changes. Runs gh, curl and `hc read`; caches issues, avatars and images
    # in ~/.config/herdr-app/data/issues/, which we do not manage.
    issues = "${inputs.herdr-issues}/mods/issues";
    # Vitals window (inputs.herdr-vitals; `nix flake update herdr-vitals`
    # to update). CPU, memory, and disks for this machine or a connected
    # one. First read downloads herdr-vitals onto that machine and runs it.
    # Not the TUI plugin.
    vitals = "${inputs.herdr-vitals}/app/mods/vitals";
    # Linear popup (inputs.herdr-linear; `nix flake update herdr-linear` to
    # update). Copied, not linked: it imports ./look.js and its own SVGs.
    # The Go binary from that same input is pre-placed below, where the mod's
    # [ -x ] check looks, so the mod does not download a release.
    linear = "${inputs.herdr-linear}/app/mods/linear";
  };

  # The mod pins this string and looks up ~/.local/share/herdr-linear/app/<it>/.
  linearVersion =
    let
      line = lib.findFirst (l: lib.hasPrefix "export const LINEAR_VERSION = " l) "" (
        lib.splitString "\n" (builtins.readFile "${inputs.herdr-linear}/app/mods/linear/main.js")
      );
      matched = builtins.match "export const LINEAR_VERSION = \"([^\"]+)\";" line;
    in
    if matched == null then
      throw "herdr-linear: LINEAR_VERSION not found in app/mods/linear/main.js"
    else
      builtins.head matched;

  herdrLinear = pkgs.callPackage ../../../packages/herdr-linear {
    src = inputs.herdr-linear;
    version = linearVersion;
  };
in
{
  config = lib.mkIf (userApps.herdr-app.enable or false) {
    home.packages = [
      (import ./package.nix { inherit pkgs; })
      herdrLinear
    ];

    # The mod never searches PATH. An executable at this exact path makes its
    # provision script print the path and exit, before curl. The script uses
    # $HOME/.local/share, not XDG_DATA_HOME.
    home.file.".local/share/herdr-linear/app/${linearVersion}/herdr-linear".source =
      lib.getExe herdrLinear;

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
      # main-issues: Herdr's main layout with the issues panel (copiedMods)
      # and its button.
      "herdr-app/layouts/main-issues.json".source = "${inputs.herdr-issues}/layouts/main-issues.json";
    };

    # Herdr T3 layout (inputs.herdr-t3; `nix flake update herdr-t3` to update).
    # Copied, not linked: see install-herdr-t3.sh. This step owns the t3-*
    # mods and layouts/herdr-t3.*; local edits to them are replaced.
    home.activation.herdrT3 = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe installHerdrT3} ${inputs.herdr-t3} "${config.xdg.configHome}/herdr-app"
    '';

    # After linkGeneration, so the old generation's links are gone first.
    home.activation.herdrMods = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe installHerdrMods} "${config.xdg.configHome}/herdr-app" ${
        lib.escapeShellArgs (lib.mapAttrsToList (name: src: "${name}=${src}") copiedMods)
      }
    '';
  };
}
