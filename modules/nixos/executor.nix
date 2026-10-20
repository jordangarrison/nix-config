{ config, lib, pkgs, ... }:

# Executor (executor.sh) self-host: one MCP gateway for personal integrations.
# The image bundles the API, MCP endpoint, auth, app runtime and dashboard over
# an embedded PGlite database. Runtime is root-managed Docker (already enabled
# in development.nix); the entrypoint drops to an unprivileged `executor` user
# inside the container.
#
# /var/lib/executor holds the database, app builds and the generated
# auth-secret.key and encryption.key. Back up the whole directory; losing the
# encryption key makes every stored credential unreadable. Stop the container
# and back it up before bumping the image tag.
let
  host = "executor.jordangarrison.dev";
  port = 4400;
  dataDir = "/var/lib/executor";
  # Same tailnet boundary as bb and day-dashboard. endeavour's host firewall
  # is off, so without this any LAN client sending this Host/SNI gets through.
  tailnetOnly = ''
    allow 127.0.0.1;
    allow ::1;
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    deny all;
  '';
in
{
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.executor = {
    image = "ghcr.io/usefulsoftwareco/executor-selfhost:2.0.0-beta.15";
    ports = [ "127.0.0.1:${toString port}:4400" ];
    volumes = [ "${dataDir}:/app/data" ];
    environment = {
      # Must match the origin the browser uses or sign-in is rejected.
      BETTER_AUTH_URL = "https://${host}";
      DO_NOT_TRACK = "1";
      # Apps may fetch private addresses, so the Norish app can reach
      # norish.garrisonsbygrace.com on the tailnet IP. This applies to every
      # app: any of them can reach the LAN, tailnet peers and endeavour's
      # 0.0.0.0 listeners. The other half is the /api/v1/ allow in norish.nix.
      EXECUTOR_APPS_ALLOW_PRIVATE_FETCH = "true";
    };
  };

  systemd.tmpfiles.rules = [ "d ${dataDir} 0755 root root -" ];

  security.acme.certs.${host} = {
    group = "nginx";
    # The system resolver (Tailscale -> blocky) caches the challenge record's
    # NXDOMAIN, so lego's propagation check times out. Check via Cloudflare.
    dnsResolver = "1.1.1.1:53";
  };

  # The dashboard's batched reads compare the browser Origin with the request
  # URL, which workerd builds as http:// because its socket ignores
  # X-Forwarded-Proto. Every other check uses BETTER_AUTH_URL. Translate only
  # our own https Origin on that route; anything else still fails the check.
  # Revisit when upgrading the image.
  services.nginx.appendHttpConfig = ''
    map $http_origin $executor_batch_origin {
      "https://${host}" "http://${host}";
      default $http_origin;
    }
  '';

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    useACMEHost = host;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      extraConfig = tailnetOnly;
    };
    locations."= /api/dashboard/batch" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = tailnetOnly + ''
        proxy_set_header Origin $executor_batch_origin;
      '';
    };
  };
}
