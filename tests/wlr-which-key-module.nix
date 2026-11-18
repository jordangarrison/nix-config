# nix build --impure --expr 'import ./tests/wlr-which-key-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = import flake.inputs.nixpkgs {
    system = "x86_64-linux";
    # The rendered menu needs the launcher's path, not a running desktop app.
    overlays = [ (final: prev: { llm-agents.herdr-app = prev.hello; }) ];
  };
  mkHome = enabled: (flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs.userApps.herdr-app.enable = enabled;
    modules = [
      ../modules/home/wlr-which-key
      {
        home.username = "developer";
        home.homeDirectory = "/home/developer";
        home.stateVersion = "25.05";
      }
    ];
  }).config;
  enabled = mkHome true;
  disabled = mkHome false;
  package = name: home: lib.findFirst (p: lib.getName p == name) null home.home.packages;
  menu = home: package "wlr-which-key-menu" home;
  launcher = package "herdr-jagpi" enabled;
in
assert package "herdr-jagpi" disabled == null;
assert launcher != null;
pkgs.runCommand "wlr-which-key-module-tests" { nativeBuildInputs = [ pkgs.jq ]; } ''
  # Read exactly the JSON file the built which-key wrapper passes to the menu.
  enabledConfig=$(sed -n 's/.* \(\/nix\/store\/[^ ]*-wlr-which-key-config.yaml\)$/\1/p' ${menu enabled}/bin/wlr-which-key-menu)
  disabledConfig=$(sed -n 's/.* \(\/nix\/store\/[^ ]*-wlr-which-key-config.yaml\)$/\1/p' ${menu disabled}/bin/wlr-which-key-menu)
  jq -e --arg launcher '${lib.getExe launcher}' '
    [.menu[] | select(.key == "j")] == [{key: "j", desc: "Jagpi (Herdr)", cmd: $launcher}]
    and ([.menu[].key] | length == (unique | length))
    and any(.menu[]; .key == "w" and any(.submenu[]; .key == "j" and .desc == "Jira Board"))
  ' "$enabledConfig"
  jq -e 'all(.menu[]; .key != "j")' "$disabledConfig"
  touch "$out"
''
