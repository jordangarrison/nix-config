{ config, lib, pkgs, ... }:

{
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "jordan@jordangarrison.dev";
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/acme-secrets/cloudflare-env";
    };
  };
}
