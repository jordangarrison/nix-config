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
  results = {
    disabledHasNoConfig = !(disabled.xdg.configFile ? "herdr-app/keys.json")
      && !(disabled.xdg.configFile ? "herdr-app/settings.json")
      && !(disabled.xdg.configFile ? "herdr-app/themes/rose-pine.json");
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
    noForcedOverwrite = !(files."herdr-app/keys.json".force)
      && !(files."herdr-app/settings.json".force)
      && !(files."herdr-app/themes/rose-pine.json".force);
    noRuntimeFiles = builtins.all (name: !(lib.hasPrefix "herdr-app/" name) || builtins.elem name [
      "herdr-app/keys.json"
      "herdr-app/settings.json"
      "herdr-app/themes/rose-pine.json"
    ]) (builtins.attrNames files);
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues results)) "Herdr app module checks failed";
results
