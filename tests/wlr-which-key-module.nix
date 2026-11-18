# nix build --impure --expr 'import ./tests/wlr-which-key-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  pkgs = import flake.inputs.nixpkgs { system = "x86_64-linux"; };
  jagpi = pkgs.writeShellScriptBin "jagpi" "exit 0";
  mkHome = { daemonHere ? false, hostname ? "discovery", herdrEnabled ? false }:
    (flake.inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        osConfig.networking.hostName = hostname;
        userApps.herdr-app.enable = herdrEnabled;
      };
      modules = [
        ../modules/home/wlr-which-key
        {
          home.username = "developer";
          home.homeDirectory = "/home/developer";
          home.stateVersion = "25.05";
        }
        {
          options.services.jagpi = {
            enable = lib.mkEnableOption "the jagpi daemon";
            package = lib.mkOption { type = lib.types.package; default = jagpi; };
          };
          config.services.jagpi.enable = daemonHere;
        }
      ];
    }).config;
  # Neither working route needs Herdr; Herdr alone cannot supply a route.
  local = mkHome { daemonHere = true; hostname = "endeavour"; };
  remote = mkHome { hostname = "opportunity"; };
  disabled = mkHome { herdrEnabled = true; };
  localOpportunity = mkHome { daemonHere = true; hostname = "opportunity"; };
  package = name: home: lib.findFirst (p: lib.getName p == name) null home.home.packages;
  menu = home: package "wlr-which-key-menu" home;
  launcher = home: package "jagpi-ghostty" home;
in
assert launcher disabled == null;
assert launcher local != null;
assert launcher remote != null;
assert launcher localOpportunity == launcher local;
assert builtins.all (home: package "herdr-jagpi" home == null) [ local remote disabled ];
pkgs.runCommand "wlr-which-key-module-tests" {
  nativeBuildInputs = [ pkgs.jq pkgs.python3 pkgs.util-linux ];
} ''
  check_menu() {
    config=$(sed -n 's/.* \(\/nix\/store\/[^ ]*-wlr-which-key-config.yaml\)$/\1/p' "$1/bin/wlr-which-key-menu")
    jq -e --arg launcher "$2" '
      [.menu[] | select(.key == "j")] == [{key: "j", desc: "Jagpi (Ghostty)", cmd: $launcher}]
      and ([.menu[].key] | length == (unique | length))
      and any(.menu[]; .key == "w" and any(.submenu[]; .key == "j" and .desc == "Jira Board"))
    ' "$config"
  }
  check_menu ${menu local} ${lib.getExe (launcher local)}
  check_menu ${menu remote} ${lib.getExe (launcher remote)}
  disabledConfig=$(sed -n 's/.* \(\/nix\/store\/[^ ]*-wlr-which-key-config.yaml\)$/\1/p' ${menu disabled}/bin/wlr-which-key-menu)
  jq -e 'all(.menu[]; .key != "j")' "$disabledConfig"

  grep -F 'set -- ${lib.getExe jagpi}' ${lib.getExe (launcher local)}
  grep -F 'set -- ssh -t endeavour jagpi' ${lib.getExe (launcher remote)}
  python3 ${./jagpi-ghostty.py} ${../modules/home/wlr-which-key/jagpi-ghostty.sh}
  touch "$out"
''
