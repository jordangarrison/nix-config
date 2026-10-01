# nix eval --json --impure --expr 'import ./tests/bb-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  mkSystem =
    modules:
    lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs.inputs = flake.inputs;
      modules = [
        ../modules/llm-agents-overlay.nix
        ../modules/nixos/bb.nix
        {
          users.users.developer = {
            isNormalUser = true;
            home = "/home/developer";
            group = "users";
          };
          system.stateVersion = "25.05";
        }
      ]
      ++ modules;
    };
  disabled = (mkSystem [ ]).config;
  base = mkSystem [
    {
      services.bb = {
        enable = true;
        user = "developer";
      };
    }
  ];
  defaults = base.config;
  enabled =
    (base.extendModules {
      modules = [
        ({ pkgs, ... }: {
          services.bb = {
            providers = {
              cursor.enable = true;
              codex.enable = true;
              pi.enable = true;
              claude.enable = true;
            };
            extraPackages = [ pkgs.ripgrep ];
            environment.BB_TEST_SETTING = "example";
            environmentFile = "/run/secrets/bb";
          };
        })
      ];
    }).config;
  custom =
    (base.extendModules {
      modules = [
        {
          services.bb = {
            group = "developers";
            home = "/srv/developer";
            dataDir = "/srv/bb state";
            port = 39999;
            bindHost = "0.0.0.0";
            openFirewall = true;
          };
          users.groups.developers = { };
        }
      ];
    }).config;
  invalid =
    (base.extendModules {
      modules = [ { services.bb.extraArgs = [ "--in-app-updates" ]; } ];
    }).config;
  host = flake.nixosConfigurations.endeavour.config;
  bbProxy = host.services.nginx.virtualHosts."bb.jordangarrison.dev";
  tests = {
    hostHttps = bbProxy.forceSSL && bbProxy.useACMEHost == "bb.jordangarrison.dev";
    hostLoopbackProxy =
      bbProxy.locations."/".proxyPass == "http://127.0.0.1:${toString host.services.bb.port}";
    hostWebSockets = bbProxy.locations."/".proxyWebsockets;
    hostTailnetOnly =
      lib.hasInfix "allow 100.64.0.0/10;" bbProxy.locations."/".extraConfig
      && lib.hasInfix "deny all;" bbProxy.locations."/".extraConfig;
    hostAppOrigin = host.services.bb.environment.BB_APP_URL == "https://bb.jordangarrison.dev";
    hostAcmeGroup = host.security.acme.certs."bb.jordangarrison.dev".group == "nginx";
    disabledHasNoUnit = !(disabled.systemd.services ? bb);
    loopbackDefault = defaults.services.bb.bindHost == "127.0.0.1";
    firewallClosedDefault = !(lib.elem 38886 defaults.networking.firewall.allowedTCPPorts);
    userDefaults =
      defaults.services.bb.home == "/home/developer"
      && defaults.services.bb.group == "users"
      && defaults.services.bb.dataDir == "/home/developer/.bb";
    credentialsOptional = !(defaults.systemd.services.bb.serviceConfig ? EnvironmentFile);
    providersOptIn = lib.all (provider: !provider.enable) (
      lib.attrValues defaults.services.bb.providers
    );
    providersOnPath = lib.all (provider: lib.elem provider.package enabled.systemd.services.bb.path) (
      lib.attrValues enabled.services.bb.providers
    );
    extraPackagesOnPath = lib.all (
      package: lib.elem package enabled.systemd.services.bb.path
    ) enabled.services.bb.extraPackages;
    credentialsRuntimeOnly =
      enabled.systemd.services.bb.serviceConfig.EnvironmentFile == "/run/secrets/bb";
    environmentAndHome =
      enabled.systemd.services.bb.environment.BB_TEST_SETTING == "example"
      && enabled.systemd.services.bb.environment.HOME == "/home/developer";
    preservesShellPath = enabled.systemd.services.bb.environment.__NIXOS_SET_ENVIRONMENT_DONE == "1";
    hostUpdatesDisabled = enabled.systemd.services.bb.environment.BB_HOST_DAEMON_AUTO_UPDATE == "0";
    bundledExecutable = lib.hasInfix ''/bin/bb-app" "start" "--bundled"'' defaults.systemd.services.bb.serviceConfig.ExecStart;
    noInAppUpdates =
      !(lib.hasInfix "--in-app-updates" defaults.systemd.services.bb.serviceConfig.ExecStart);
    rejectsUpdates = lib.any (
      a: !a.assertion && lib.hasPrefix "services.bb:" a.message
    ) invalid.assertions;
    customPathsQuoted = lib.hasInfix ''"--data-dir" "/srv/bb state"'' custom.systemd.services.bb.serviceConfig.ExecStart;
    customUserSettings =
      custom.systemd.services.bb.serviceConfig.Group == "developers"
      && custom.systemd.services.bb.environment.HOME == "/srv/developer";
    firewallOptIn = lib.elem 39999 custom.networking.firewall.allowedTCPPorts;
    privateState = defaults.systemd.tmpfiles.settings."10-bb"."/home/developer/.bb".d.mode == "0700";
    noWarnings = defaults.warnings == [ ] && enabled.warnings == [ ] && custom.warnings == [ ];
    oneSupervisor =
      !(enabled.systemd.services ? bb-server) && !(enabled.systemd.services ? bb-host-daemon);
  };
in
assert lib.assertMsg (lib.all (result: result) (lib.attrValues tests))
  "bb module tests failed: ${
    lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: result: !result) tests))
  }";
tests
