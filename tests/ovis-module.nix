# nix eval --json --impure --expr 'import ./tests/ovis-module.nix { flake = builtins.getFlake (toString ./.); }'
{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  host = flake.nixosConfigurations.endeavour.config;
  pkgs = flake.nixosConfigurations.endeavour.pkgs;
  mkHome = userApps: piEnabled: (flake.inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit userApps; };
    modules = [
      ../modules/home/ovis
      ../modules/home/pi
      {
        programs.pi.enable = piEnabled;
        home.username = "developer";
        home.homeDirectory = "/home/developer";
        home.stateVersion = "25.05";
      }
    ];
  }).config;
  disabled = mkHome { } true;
  enabled = mkHome { ovis.enable = true; } true;
  withoutPi = mkHome { ovis.enable = true; } false;
  service = enabled.systemd.user.services.ovis;
  hostService = host.home-manager.users.jordangarrison.systemd.user.services.ovis;
  proxy = host.services.nginx.virtualHosts."ovis.jordangarrison.dev";
  proxyConfig = proxy.locations."/".extraConfig;
  results = {
    disabledHasNoService = !(disabled.systemd.user.services ? ovis);
    disabledHasNoPackage = !(lib.elem pkgs.llm-agents.ovis disabled.home.packages);
    installsPublishedPackage = lib.elem pkgs.llm-agents.ovis enabled.home.packages;
    piIntegrationNeedsOvis = !(disabled.programs.pi.extensions.files ? "herdr-web-ui.js");
    piIntegrationNeedsPi = !(withoutPi.programs.pi.extensions.files ? "herdr-web-ui.js");
    piIntegrationManaged =
      enabled.home.file.".pi/agent/extensions/herdr-web-ui.js".source
      == enabled.programs.pi.extensions.files."herdr-web-ui.js".source;
    hostPiIntegration = host.home-manager.users.jordangarrison.home.file ? ".pi/agent/extensions/herdr-web-ui.js";
    runsAtLogin = lib.elem "default.target" service.Install.WantedBy;
    usesPublishedEntrypoint = service.Service.ExecStart == [ (lib.getExe pkgs.llm-agents.ovis) ];
    loopbackOnly = lib.elem "HOST=127.0.0.1" service.Service.Environment;
    servesCore = lib.elem "OVIS_RUNTIME=herdr-core" service.Service.Environment;
    coreStaysSelfManaged =
      lib.elem "OVIS_HC_BIN=/home/developer/.local/bin/hc" service.Service.Environment
      && !(lib.elem pkgs.llm-agents.herdr-core enabled.home.packages);
    noTelemetry = lib.elem "OVIS_TELEMETRY=0" service.Service.Environment;
    requiredRuntimeSecret = service.Service.EnvironmentFile == "/home/developer/.config/ovis/token.env";
    rejectsEmptyToken = lib.hasInfix "ovis-check-token" service.Service.ExecStartPre;
    privateFiles = service.Service.UMask == "0077";
    serviceRestarts = service.Service.Restart == "on-failure";
    hostEnabled = host.users.jordangarrison.apps.ovis.enable;
    hostRequiredSecret = hostService.Service.EnvironmentFile == "/home/jordangarrison/.config/ovis/token.env";
    https = proxy.forceSSL && proxy.useACMEHost == "ovis.jordangarrison.dev";
    certOwnedByNginx = host.security.acme.certs."ovis.jordangarrison.dev".group == "nginx";
    correctBackend = proxy.locations."/".proxyPass == "http://127.0.0.1:7317";
    websockets = proxy.locations."/".proxyWebsockets;
    tailnetOnly =
      lib.hasInfix "allow 100.64.0.0/10;" proxyConfig
      && lib.hasInfix "allow fd7a:115c:a1e0::/48;" proxyConfig
      && lib.hasInfix "deny all;" proxyConfig;
    forwardsOrigin =
      !proxy.locations."/".recommendedProxySettings
      && lib.hasInfix "proxy_set_header Host $host;" proxyConfig
      && lib.hasInfix "proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;" proxyConfig
      && lib.hasInfix "proxy_set_header X-Forwarded-Proto $scheme;" proxyConfig;
    stripsForgedTailscaleIdentity = lib.hasInfix ''proxy_set_header Tailscale-User-Login "";'' proxyConfig;
    noDirectFirewallPort = !(lib.elem 7317 host.networking.firewall.allowedTCPPorts);
  };
in
assert lib.assertMsg (lib.all (x: x) (lib.attrValues results))
  "Ovis module checks failed: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: result: !result) results))}";
results
