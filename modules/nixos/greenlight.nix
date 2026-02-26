{ config, lib, pkgs, ... }:

{
  services.greenlight = {
    enable = true;
    host = "endeavour";
    port = 4444;
    listenAddress = "0.0.0.0";
    githubTokenFile = "/var/lib/greenlight/secrets/github-token";
    secretKeyBaseFile = "/var/lib/greenlight/secrets/secret-key-base";
    bookmarkedRepos = [
      "jordangarrison/nix-config"
      "jordangarrison/sweet-nothings"
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
