# nix eval --json --impure --expr 'import ./tests/t3code-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  mkSystem = extra: lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs.inputs = flake.inputs;
    modules = [
      ../modules/llm-agents-overlay.nix
      ../modules/nixos/t3code.nix
      {
        users.users.developer = {
          isNormalUser = true;
          home = "/home/developer";
          group = "users";
        };
        system.stateVersion = "25.05";
      }
      extra
    ];
  };
  disabled = (mkSystem { }).config;
  enabled = (mkSystem {
    services.t3code = { enable = true; user = "developer"; };
  }).config;
  service = enabled.systemd.services.t3code;
  host = flake.nixosConfigurations.endeavour.config;
  proxy = host.services.nginx.virtualHosts."t3code.jordangarrison.dev";
  results = {
    disabledHasNoService = !(disabled.systemd.services ? t3code);
    runsAtBoot = builtins.elem "multi-user.target" service.wantedBy;
    nonRoot = service.serviceConfig.User == "developer";
    home = service.environment.HOME == "/home/developer";
    loopbackOnly = lib.hasInfix "127.0.0.1" service.serviceConfig.ExecStart;
    separateState = lib.hasInfix "/home/developer/.local/share/t3code-server" service.serviceConfig.ExecStart;
    privateState = enabled.systemd.tmpfiles.settings."10-t3code"."/home/developer/.local/share/t3code-server".d.mode == "0700";
    privateFiles = service.serviceConfig.UMask == "0077";
    noPairingInJournal = service.serviceConfig.StandardOutput == "null";
    stopAgentsTogether = service.serviceConfig.KillMode == "control-group";
    noFirewallPort = !(builtins.elem 3773 enabled.networking.firewall.allowedTCPPorts);
    https = proxy.forceSSL && proxy.useACMEHost == "t3code.jordangarrison.dev";
    websockets = proxy.locations."/".proxyWebsockets;
    correctBackend = proxy.locations."/".proxyPass == "http://127.0.0.1:3773";
    tailnetOnly = lib.hasInfix "allow 100.64.0.0/10;" proxy.locations."/".extraConfig
      && lib.hasInfix "deny all;" proxy.locations."/".extraConfig;
  };
in
assert lib.assertMsg (lib.all (x: x) (builtins.attrValues results)) "T3 Code module checks failed";
results
