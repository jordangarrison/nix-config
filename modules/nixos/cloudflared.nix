{ ... }:

{
  # Cloudflare Tunnel for public internet access to panko.
  # Tunnel created with: cloudflared tunnel create panko
  # Credentials file must be readable by the cloudflared user (0600, cloudflared:cloudflared).
  services.cloudflared = {
    enable = true;
    tunnels."71e2092b-5e07-4125-8329-f538bdc58d48" = {
      credentialsFile = "/var/lib/cloudflared/panko.json";
      default = "http_status:404";
      ingress = {
        "panko.jordangarrison.dev" = "http://localhost:4001";
      };
    };
  };
}
