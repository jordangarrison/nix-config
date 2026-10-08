{ config, inputs, lib, pkgs, ... }:

{
  # nixpkgs' Greenlight is the unrelated BigBlueButton frontend; use our
  # GitHub dashboard module from inputs.greenlight instead.
  disabledModules = [ "services/web-apps/greenlight.nix" ];
  # Apply the same exclusion when generating option docs; otherwise the
  # upstream module's descriptions look up database options our app lacks.
  documentation.nixos.includeAllModules = true;

  services.greenlight = {
    enable = true;
    package = inputs.greenlight.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      # mixRelease uses structured attrs now: top-level variables aren't
      # exported to Mix. Keep Tailwind offline using the packaged binary.
      preBuild = ''
        export MIX_TAILWIND_PATH=${lib.escapeShellArg old.MIX_TAILWIND_PATH}
      '' + (old.preBuild or "");
    });
    host = "endeavour";
    port = 4444;
    listenAddress = "0.0.0.0";
    githubTokenFile = "/var/lib/greenlight/secrets/github-token";
    secretKeyBaseFile = "/var/lib/greenlight/secrets/secret-key-base";
    bookmarkedRepos = [
      "jordangarrison/nix-config"
      "jordangarrison/sweet-nothings"
      "jordangarrison/focus-fox"
      "jordangarrison/wiggle-puppy"
      "jordangarrison/panko"
      "flocasts/web-monorepo"
      "flocasts/infra-base-services"
      "flocasts/flosports30"
      "flocasts/experience-service"
      "flocasts/helm-charts"
    ];
    allowedOrigins = [
      "//*.ts.net"
      "//endeavour:4444"
      "//greenlight.jordangarrison.dev"
    ];
    followedOrgs = [
      "NixOS"
      "flocasts"
      "milesplit"
      "DirectAthletics"
      "HockeyTech"
      "KartingCoach"
    ];
  };

  security.acme.certs."greenlight.jordangarrison.dev" = {
    group = "nginx";
  };

  services.nginx.virtualHosts."greenlight.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "greenlight.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://localhost:4444";
      proxyWebsockets = true;
    };
  };
}
