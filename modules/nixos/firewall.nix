{ config, ... }:

# Network boundary for the NixOS hosts. Three zones:
#
#   loopback  Always trusted.
#   tailnet   The Tailscale interface is trusted. Tailscale ACLs decide who is
#             on the tailnet; a service that needs more adds its own login or
#             an nginx allow list. A per-port list here would break Tailscale's
#             own peer API (Taildrop, exit-node DNS), which uses a port that
#             tailscaled picks at run time.
#   other     Home LAN, Wi-Fi and Docker bridges: closed by default. A service
#             module opens a port here only when a device that is not on the
#             tailnet needs it, and says why next to the port.
#
# Docker-published ports skip this filter (Docker forwards them in its own
# nat rules), so publish container ports on 127.0.0.1 only.
{
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ config.services.tailscale.interfaceName ];
  };

  # Direct WireGuard paths between peers instead of DERP relays.
  services.tailscale.openFirewall = true;
}
