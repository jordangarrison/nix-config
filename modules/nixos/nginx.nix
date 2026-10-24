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
      # Bypass the Tailscale/local caching resolver for transient ACME TXT
      # challenges; stale NXDOMAIN responses can otherwise block renewals.
      dnsResolver = "1.1.1.1:53";
      environmentFile = "/var/lib/acme-secrets/cloudflare-env";
    };
  };
}
