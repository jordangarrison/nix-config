{ config, lib, pkgs, ... }:

# Norish (norish.dev) self-host: household recipes, meal plans and groceries.
# Upstream ships only Docker images (a pnpm monorepo plus an embedded Python
# parser), so the app and Obscura, its headless browser for URL imports, run
# as root-managed Docker containers. Postgres and Redis are the host's own.
#
# The app container uses host networking so it reaches Postgres and Redis on
# 127.0.0.1 under the existing localhost trust rule; it binds 127.0.0.1 only.
#
# /var/lib/norish/secrets holds the generated MASTER_KEY. Back it up with the
# norish database; losing it makes encrypted data unreadable. Back up uploads/
# too. Stop the container before bumping the image tag.
let
  host = "nourish.garrisonsbygrace.com";
  port = 3010;
  # Embedded parser API, loopback-only on the host network. Off the default
  # 8001 to avoid colliding with other local services.
  parserPort = 3011;
  obscuraPort = 3012;
  redisPort = 6390;
  dataDir = "/var/lib/norish";
  secretsDir = "${dataDir}/secrets";
  # Same tailnet boundary as executor. endeavour's host firewall is off, so
  # without this any LAN client sending this Host/SNI gets through.
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

  virtualisation.oci-containers.containers.norish = {
    image = "docker.io/norishapp/norish:v0.25.1-beta";
    extraOptions = [
      "--network=host"
      # The image's healthcheck hardcodes localhost:3000; probe our port.
      "--health-cmd=node -e \"require('http').get('http://127.0.0.1:${toString port}/api/v1/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))\""
    ];
    volumes = [ "${dataDir}/uploads:/app/uploads" ];
    environmentFiles = [ "${secretsDir}/norish.env" ];
    environment = {
      AUTH_URL = "https://${host}";
      HOST = "127.0.0.1";
      PORT = toString port;
      PARSER_API_PORT = toString parserPort;
      DATABASE_URL = "postgres://norish@127.0.0.1:5432/norish";
      REDIS_URL = "redis://127.0.0.1:${toString redisPort}";
      OBSCURA_ENDPOINT = "ws://127.0.0.1:${toString obscuraPort}";
      UPLOADS_DIR = "/app/uploads";
      # First user signs up with a password and becomes admin; further auth
      # providers are configured in Settings => Admin.
      PASSWORD_AUTH_ENABLED = "true";
    };
  };

  virtualisation.oci-containers.containers.norish-obscura = {
    # Keep in step with docker/obscura/pin.env for the Norish release above.
    image = "docker.io/norishapp/obscura:0.2.4-norish.1";
    ports = [ "127.0.0.1:${toString obscuraPort}:9222" ];
    environmentFiles = [ "${secretsDir}/obscura.env" ];
  };

  # Generate secrets once; never overwrite. MASTER_KEY derives the encryption
  # keys, so it must stay stable for the life of the database.
  systemd.services.norish-secrets = {
    description = "Generate Norish secrets";
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    path = [ pkgs.openssl pkgs.coreutils ];
    script = ''
      umask 077
      mkdir -p ${secretsDir}
      if [ ! -s ${secretsDir}/norish.env ]; then
        token=$(openssl rand -hex 32)
        printf 'MASTER_KEY=%s\nOBSCURA_CDP_TOKEN=%s\n' \
          "$(openssl rand -base64 32)" "$token" > ${secretsDir}/norish.env
        printf 'OBSCURA_CDP_TOKEN=%s\n' "$token" > ${secretsDir}/obscura.env
      fi
    '';
  };

  systemd.services.docker-norish = {
    requires = [ "norish-secrets.service" "postgresql.service" "redis-norish.service" ];
    after = [ "norish-secrets.service" "postgresql.service" "redis-norish.service" "docker-norish-obscura.service" ];
  };
  systemd.services.docker-norish-obscura = {
    requires = [ "norish-secrets.service" ];
    after = [ "norish-secrets.service" ];
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root -"
    # The entrypoint hands uploads to the image's uid/gid 1000 on every start;
    # match it so tmpfiles doesn't flip ownership back.
    "d ${dataDir}/uploads 0750 1000 1000 -"
  ];

  services.postgresql = {
    ensureDatabases = [ "norish" ];
    ensureUsers = [
      {
        name = "norish";
        ensureDBOwnership = true;
      }
    ];
  };

  services.redis.servers.norish = {
    enable = true;
    bind = "127.0.0.1";
    port = redisPort;
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
      # Real-time sync (tRPC subscriptions) runs over websockets.
      proxyWebsockets = true;
      extraConfig = tailnetOnly + ''
        client_max_body_size 50m;
      '';
    };
  };
}
