{ config, lib, pkgs, ... }:

{
  # nginx is for the tailnet (trusted by modules/nixos/firewall.nix) and for
  # Docker containers, which reach it on endeavour's own addresses:
  #   docker0  Executor apps call Norish's vhost (see norish.nix).
  #   br-+     Forgejo Actions jobs run on per-job bridge networks and clone
  #            from forgejo.jordangarrison.dev. "+" is iptables' wildcard; if
  #            networking.nftables is turned on, this must change to "br-*".
  # The LAN gets no web ports. The public sites come in through cloudflared,
  # which connects to nginx on loopback.
  networking.firewall.interfaces = lib.genAttrs [ "docker0" "br-+" ] (_: {
    allowedTCPPorts = [ 80 443 ];
  });

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
