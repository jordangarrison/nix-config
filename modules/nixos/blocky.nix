# modules/nixos/blocky.nix
#
# DNS-level ad blocker and privacy filter using Blocky.
#
# Provides network-wide ad/tracker/malware blocking via DNS with:
# - DNS-over-HTTPS upstream resolution (Cloudflare + Quad9)
# - Hagezi Pro + StevenBlack ad lists, Hagezi TIF threat list, adult content filter
# - Per-client group filtering (default + kids)
# - Tailscale MagicDNS conditional forwarding
# - Prometheus metrics endpoint
# - Nginx reverse proxy with ACME TLS
#
# Manual steps after enabling:
# 1. Create a DNS record for blocky.garrisonsbygrace.com pointing to endeavour
# 2. Find device IPs for the kids group and add them to the clients list
# 3. Point other network devices to endeavour's IP for DNS (port 53)
#
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dns-blocking;
in
{
  options.services.dns-blocking = {
    enable = mkEnableOption "DNS-level ad blocking and privacy filtering (Blocky)";
  };

  config = mkIf cfg.enable {
    # --- Blocky DNS proxy ---
    services.blocky = {
      enable = true;
      settings = {
        # Listener ports
        ports = {
          dns = 53;
          http = 8053;
        };

        # Upstream DNS-over-HTTPS resolvers
        upstreams = {
          groups = {
            default = [
              "https://one.one.one.one/dns-query"
              "https://dns.quad9.net/dns-query"
            ];
          };
        };

        # Bootstrap DNS for resolving DoH hostnames on first boot
        bootstrapDns = {
          upstream = "https://one.one.one.one/dns-query";
          ips = [ "1.1.1.1" "9.9.9.9" ];
        };

        # Blocklists
        blocking = {
          denylists = {
            ads = [
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt"
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
            ];
            security = [
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/tif.txt"
            ];
            adult = [
              "https://blocklistproject.github.io/Lists/porn.txt"
            ];
          };

          # Client group -> blocklist mapping
          clientGroupsBlock = {
            default = [ "ads" "security" "adult" ];
            kids = [ "ads" "security" "adult" ];
          };

          blockType = "zeroIp";
        };

        # Client definitions
        clientLookup = {
          clients = {
            # TODO: Add device IPs for the kids group
            # kids = [ "192.168.1.100" "192.168.1.101" ];
          };
        };

        # Conditional forwarding
        conditional = {
          mapping = {
            # Tailscale MagicDNS — resolves *.ts.net device names
            "ts.net" = "100.100.100.100";
            # TODO: Uncomment and set your router IP for local LAN names
            # "lan" = "192.168.1.1";
          };
        };

        # Caching
        caching = {
          minTime = "5m";
          maxTime = "30m";
          prefetching = true;
        };

        # Prometheus metrics
        prometheus = {
          enable = true;
          path = "/metrics";
        };

        # Query logging (console for now, visible via journalctl -u blocky)
        queryLog = {
          type = "console";
        };

        # Application logging
        log = {
          level = "info";
        };
      };
    };

    # --- System integration ---

    # Disable systemd-resolved to free port 53
    services.resolved.enable = false;

    # Use Blocky for local DNS resolution
    networking.nameservers = [ "127.0.0.1" ];

    # Open firewall for DNS (LAN + Tailscale clients)
    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };

    # --- Nginx reverse proxy ---

    security.acme.certs."blocky.garrisonsbygrace.com" = {
      group = "nginx";
    };

    services.nginx.virtualHosts."blocky.garrisonsbygrace.com" = {
      forceSSL = true;
      useACMEHost = "blocky.garrisonsbygrace.com";
      locations."/" = {
        proxyPass = "http://localhost:8053";
      };
    };
  };
}
