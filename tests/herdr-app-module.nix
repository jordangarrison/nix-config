# nix eval --json --impure --expr 'import ./tests/herdr-app-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = import flake.inputs.nixpkgs {
    system = "x86_64-linux";
    overlays = [ (final: prev: { llm-agents.herdr-app = prev.hello; }) ];
  };
  mkHome = enabled: daemonHere: (flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inputs.herdr-t3 = flake.inputs.herdr-t3;
      inputs.herdr-space-folders = flake.inputs.herdr-space-folders;
      inputs.herdr-issues = flake.inputs.herdr-issues;
      inputs.herdr-vitals = flake.inputs.herdr-vitals;
      inputs.herdr-linear = flake.inputs.herdr-linear;
      inputs.herdr-revive = flake.inputs.herdr-revive;
      inputs.jagpi = flake.inputs.jagpi;
      userApps.herdr-app.enable = enabled;
    };
    modules = [
      ../modules/home/herdr-app
      {
        home.username = "developer";
        home.homeDirectory = "/home/developer";
        home.stateVersion = "25.05";
      }
      # Stands in for jagpi's module: the host that runs the daemon.
      {
        options.services.jagpi.enable = lib.mkEnableOption "the jagpi daemon";
        config.services.jagpi.enable = daemonHere;
      }
    ];
  }).config;
  # A host without the jagpi daemon (its board reads endeavour's), the host
  # that runs it, and Herdr app off.
  enabled = mkHome true false;
  daemonHost = mkHome true true;
  disabled = mkHome false false;
  # Every jagpi-board content anywhere in the layout (blocks, stack
  # headers): its props, or {} without any.
  boardProps =
    value:
    if builtins.isList value then
      lib.concatMap boardProps value
    else if builtins.isAttrs value then
      lib.optional ((value.mod or null) == "jagpi-board") (value.props or { })
      ++ lib.concatMap boardProps (builtins.attrValues value)
    else
      [ ];
  jagpiLayout = builtins.fromJSON (builtins.readFile files."herdr-app/layouts/jagpi.json".source);
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
    "herdr-app/mods/atuin-threads/mod.json"
    "herdr-app/mods/atuin-threads/main.js"
    "herdr-app/mods/atuin-threads/threads.svg"
    "herdr-app/layouts/main-folders.json"
    "herdr-app/mods/space-folders/mod.json"
    "herdr-app/mods/space-folders/main.js"
    "herdr-app/layouts/main-issues.json"
    "herdr-app/layouts/jagpi.json"
    "herdr-app/layouts/jagpi.svg"
  ];
  results = {
    disabledHasNoConfig = builtins.all (name: !(disabled.xdg.configFile ? name)) managed;
    disabledHasNoPackage = !(builtins.elem pkgs.hello disabled.home.packages);
    enabledHasPackage = builtins.elem pkgs.hello enabled.home.packages;
    focusKeys = keys.global.alt-h == "pane.go:left"
      && keys.global.alt-j == "pane.go:down"
      && keys.global.alt-k == "pane.go:up"
      && keys.global.alt-l == "pane.go:right";
    atuinThreadsKey = keys.global.ctrl-shift-r == "mod.open:atuin-threads";
    vitalsKey = keys.global."cmd-alt-v" == "mod.open:vitals"
      && keys."mod:vitals".escape == "vitals.close";
    spaceKeys = keys.global.alt-shift-j == "space.next"
      && keys.global.alt-shift-k == "space.prev";
    tabKeys = keys.global."alt-{" == "tab.prev"
      && keys.global."alt-}" == "tab.next"
      && keys.global."alt-shift-[" == "tab.prev"
      && keys.global."alt-shift-]" == "tab.next";
    preservedDefaults = keys.terminal.ctrl-shift-c == "terminal.copy"
      && keys.global.ctrl-shift-p == "app.palette";
    herdrT3Keys = keys."layout:herdr-t3".cmd-shift-b == "t3-tabs.sidebar"
      && keys."layout:herdr-t3".ctrl-shift-f == "t3-tabs.sidebar"
      && keys."layout:herdr-t3".ctrl-shift-s == "t3-tabs.settle"
      && keys."mod:t3-picker".ctrl-alt-x == "overlay.close";
    spaceFolders = lib.hasInfix ''"mod": "space-folders"'' (builtins.readFile files."herdr-app/layouts/main-folders.json".source)
      && keys."layout:main-folders".alt-shift-j == "space-folders.next"
      && keys."layout:main-folders".alt-shift-k == "space-folders.prev"
      && !(keys."layout:main-folders" ? alt-down);
    herdrT3Installed = enabled.home.activation ? herdrT3
      && lib.hasInfix "install-herdr-t3" enabled.home.activation.herdrT3.data
      && !(disabled.home.activation ? herdrT3);
    # Multi-file mods are copied, never linked: linked relative imports fail.
    herdrModsInstalled = enabled.home.activation ? herdrMods
      && lib.hasInfix "install-herdr-mods" enabled.home.activation.herdrMods.data
      && lib.hasInfix "issues=" enabled.home.activation.herdrMods.data
      && lib.hasInfix "vitals=" enabled.home.activation.herdrMods.data
      && lib.hasInfix "linear=" enabled.home.activation.herdrMods.data
      && !(files ? "herdr-app/mods/linear/main.js")
      && !(files ? "herdr-app/mods/issues/main.js")
      && !(files ? "herdr-app/mods/vitals/main.js")
      && !(disabled.home.activation ? herdrMods);
    # jagpi's mod imports its siblings: copied, never linked.
    jagpiBoardInstalled = lib.hasInfix "jagpi-board=" enabled.home.activation.herdrMods.data
      && lib.hasInfix "integrations/herdr-app/mods/jagpi-board" enabled.home.activation.herdrMods.data
      && !(files ? "herdr-app/mods/jagpi-board/main.js");
    # Revive also needs its sibling files, so copy it without replacing the board.
    reviveInstalled = lib.hasInfix "revive=" enabled.home.activation.herdrMods.data
      && !(files ? "herdr-app/mods/revive/main.js")
      && keys.global.ctrl-alt-r == "mod.open:revive"
      && keys.global.cmd-shift-r == "mod.open:revive";
    # Every jagpi-board block names the daemon's machine; roles stay.
    jagpiBoardMachine =
      let
        props = boardProps jagpiLayout;
      in
      builtins.any (p: !(p ? role)) props
      && builtins.any (p: (p.role or null) == "top") props
      && builtins.any (p: (p.role or null) == "tabs") props
      && builtins.all (p: p.machine == "endeavour") props;
    # On the daemon's host, the upstream layout as it is, and the same mod.
    jagpiLocalLayout = lib.hasSuffix "integrations/herdr-app/layouts/jagpi.json"
      (toString daemonHost.xdg.configFile."herdr-app/layouts/jagpi.json".source)
      && lib.hasInfix "jagpi-board=" daemonHost.home.activation.herdrMods.data;
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
