{ config, lib, pkgs, ... }:

# isp-snitch (https://github.com/mago0/isp-snitch): probes the ISP uplink and
# keeps a history of latency, loss and outages. The service module comes from
# the isp-snitch flake input; this file sets it up for endeavour and puts it
# behind nginx.
#
# isp-snitch has no login, so the tailnet allow list below is the only access
# control. DNS: isp-snitch.jordangarrison.dev is an A record to the Tailscale
# IP. endeavour's host firewall is off and nginx routes by Host, so without the
# allow list any LAN client sending this Host/SNI gets through.
let
  host = "isp-snitch.jordangarrison.dev";
  port = 9180;
in
{
  services.isp-snitch = {
    enable = true;
    # Loopback only; nginx is the front door.
    openFirewall = false;
    settings = {
      # endeavour has two uplinks to the same gateway: enp42s0 (metric 100)
      # and wlo1 (metric 600). Bind probes to the wired one so a fallback to
      # Wi-Fi shows up as a fault instead of silently changing the path.
      interface = "enp42s0";
      listen = "127.0.0.1:${toString port}";
    };
  };

  security.acme.certs.${host} = {
    group = "nginx";
    # The system resolver (Tailscale -> blocky) caches the challenge record's
    # NXDOMAIN, so lego's propagation check times out. Check via Cloudflare.
    dnsResolver = "1.1.1.1:53";
  };

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    useACMEHost = host;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;
      '';
    };
  };
}
