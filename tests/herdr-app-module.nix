# nix eval --json --impure --expr 'import ./tests/herdr-app-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  mkHome = enabled: (flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inputs.herdr-app.packages.x86_64-linux.herdr-app = pkgs.hello;
      userApps.herdr-app.enable = enabled;
    };
    modules = [
      ../modules/home/herdr-app
      {
        home.username = "developer";
        home.homeDirectory = "/home/developer";
        home.stateVersion = "25.05";
      }
    ];
  }).config;
  enabled = mkHome true;
  disabled = mkHome false;
  files = enabled.xdg.configFile;
  keys = builtins.fromJSON (builtins.readFile files."herdr-app/keys.json".source);
  settings = builtins.fromJSON (builtins.readFile files."herdr-app/settings.json".source);
  theme = builtins.fromJSON (builtins.readFile files."herdr-app/themes/rose-pine.json".source);
  workLayout = builtins.fromJSON (builtins.readFile files."herdr-app/layouts/work-items.json".source);
  workMod = builtins.fromJSON (builtins.readFile files."herdr-app/mods/work-items/mod.json".source);
  workItemsJs = builtins.readFile files."herdr-app/mods/work-items/main.js".source;
  managed = [
    "herdr-app/keys.json"
    "herdr-app/settings.json"
    "herdr-app/themes/rose-pine.json"
    "herdr-app/layouts/work-items.json"
    "herdr-app/layouts/work-items.svg"
    "herdr-app/mods/work-items/mod.json"
    "herdr-app/mods/work-items/main.js"
    "herdr-app/mods/work-agents/mod.json"
    "herdr-app/mods/work-agents/main.js"
    "herdr-app/mods/subscription-usage/mod.json"
    "herdr-app/mods/subscription-usage/main.js"
  ];
  results = {
    disabledHasNoConfig = builtins.all (name: !(disabled.xdg.configFile ? name)) managed;
    disabledHasNoPackage = !(builtins.elem pkgs.hello disabled.home.packages);
    enabledHasPackage = builtins.elem pkgs.hello enabled.home.packages;
    focusKeys = keys.global.alt-h == "pane.go:left"
      && keys.global.alt-j == "pane.go:down"
      && keys.global.alt-k == "pane.go:up"
      && keys.global.alt-l == "pane.go:right";
    spaceKeys = keys.global.alt-shift-j == "space.next"
      && keys.global.alt-shift-k == "space.prev";
    tabKeys = keys.global."alt-{" == "tab.prev"
      && keys.global."alt-}" == "tab.next"
      && keys.global."alt-shift-[" == "tab.prev"
      && keys.global."alt-shift-]" == "tab.next";
    preservedDefaults = keys.terminal.ctrl-shift-c == "terminal.copy"
      && keys.global.ctrl-shift-p == "app.palette";
    soundsDisabled = !settings.sounds.enabled;
    terminalFont = settings.font == "Source Code Pro";
    rosePine = settings.theme == "rose-pine" && theme.background == "#191724"
      && theme.foreground == "#e0def4" && builtins.length theme.ansi == 16;
    noForcedOverwrite = builtins.all (name: !(files.${name}.force)) managed;
    noRuntimeFiles = builtins.all (name: !(lib.hasPrefix "herdr-app/" name) || builtins.elem name managed) (builtins.attrNames files);
    workItemsLayout = workLayout.id == "root"
      && workLayout.preview == "layouts/work-items.svg"
      && lib.hasInfix ''"mod": "work-items"'' (builtins.readFile files."herdr-app/layouts/work-items.json".source)
      && lib.hasInfix ''"mod": "work-agents"'' (builtins.readFile files."herdr-app/layouts/work-items.json".source)
      && lib.hasInfix ''"mod": "subscription-usage"'' (builtins.readFile files."herdr-app/layouts/work-items.json".source);
    workItemsMod = workMod.place == "none"
      # Each managed file links to its own store path, so a relative import
      # resolves outside the app folder and the app refuses the mod.
      && !(lib.hasInfix ''from "./'' workItemsJs)
      && lib.hasInfix "// ==== MODEL BEGIN ====" workItemsJs
      && lib.hasInfix ''LABEL = "work.item"'' workItemsJs
      && lib.hasInfix ''LIST_FILE = ".config/herdr-app/work-items.json"'' workItemsJs;
    xaiUsage = lib.hasInfix "cli-chat-proxy.grok.com/v1/billing?format=credits" (builtins.readFile files."herdr-app/mods/subscription-usage/main.js".source)
      && lib.hasInfix "creditUsagePercent" (builtins.readFile files."herdr-app/mods/subscription-usage/main.js".source);
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues results)) "Herdr app module checks failed";
results
