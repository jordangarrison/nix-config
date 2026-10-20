{ config, lib, pkgs, ... }:

# Norish (norish.dev) self-host: household recipes, meal plans and groceries.
# Upstream ships only Docker images (a pnpm monorepo plus an embedded Python
# parser), so the app and Obscura, its headless browser for URL imports, run
# as root-managed Docker containers. Postgres and Redis are the host's own.
#
# The app container uses host networking so it reaches Postgres and Redis on
# 127.0.0.1; it binds 127.0.0.1 only. It connects as the passwordless norish
# role, which postgres.nix's trust rules admit from localhost and the tailnet.
# It runs as its own norish uid, not the image's 1000, which is jordangarrison
# here and would reach his X11 session over the shared network namespace.
#
# /var/lib/norish/secrets holds the generated MASTER_KEY. Back it up with the
# norish database; losing it makes encrypted data unreadable. Back up uploads/
# too. Every start migrates the database forward. Before bumping the image
# tag, dump the norish database and read the release's upgrade notes. A Nix
# rollback doesn't roll back the schema; restore the dump instead.
let
  host = "norish.garrisonsbygrace.com";
  port = 3010;
  # Embedded parser API, loopback-only on the host network. Off the default
  # 8001 to avoid colliding with other local services.
  parserPort = 3011;
  obscuraPort = 3012;
  redisPort = 6390;
  uid = 970;
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
  # Executor runs on Docker's default bridge and reaches this vhost through
  # the host, so its requests arrive from that subnet. Only /api/v1/ is open
  # to it: key-authenticated except /health. It also admits every other
  # default-bridge container. The other half is EXECUTOR_APPS_ALLOW_PRIVATE_FETCH
  # in executor.nix.
  dockerBridge = "172.17.0.0/16";
in
{
  virtualisation.oci-containers.backend = "docker";

  virtualisation.oci-containers.containers.norish = {
    image = "docker.io/norishapp/norish:v0.25.1-beta";
    extraOptions = [
      "--network=host"
      "--user=${toString uid}:${toString uid}"
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
      DATABASE_URL = "postgres://norish@127.0.0.1:${toString config.services.postgresql.settings.port}/norish";
      REDIS_URL = "redis://127.0.0.1:${toString redisPort}";
      OBSCURA_ENDPOINT = "ws://127.0.0.1:${toString obscuraPort}";
      UPLOADS_DIR = "/app/uploads";
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
    path = [ pkgs.openssl pkgs.coreutils pkgs.gnugrep ];
    # Each file has its own guard and is written atomically, so an interrupted
    # run or a deleted obscura.env repairs itself from norish.env.
    script = ''
      umask 077
      mkdir -p ${secretsDir}
      if [ ! -s ${secretsDir}/norish.env ]; then
        printf 'MASTER_KEY=%s\nOBSCURA_CDP_TOKEN=%s\n' \
          "$(openssl rand -base64 32)" "$(openssl rand -hex 32)" > ${secretsDir}/norish.env.tmp
        mv ${secretsDir}/norish.env.tmp ${secretsDir}/norish.env
      fi
      if [ ! -s ${secretsDir}/obscura.env ]; then
        grep '^OBSCURA_CDP_TOKEN=' ${secretsDir}/norish.env > ${secretsDir}/obscura.env.tmp
        mv ${secretsDir}/obscura.env.tmp ${secretsDir}/obscura.env
      fi
    '';
  };

  # postgresql.target waits for postgresql-setup, which creates the role and
  # database.
  systemd.services.docker-norish = {
    requires = [ "norish-secrets.service" "postgresql.target" "redis-norish.service" ];
    after = [ "norish-secrets.service" "postgresql.target" "redis-norish.service" "docker-norish-obscura.service" ];
    # Admin => "Restart server" exits 0 and expects the runtime to bring it back.
    serviceConfig.Restart = lib.mkForce "always";
  };
  systemd.services.docker-norish-obscura = {
    requires = [ "norish-secrets.service" ];
    after = [ "norish-secrets.service" ];
  };

  users.users.norish = {
    inherit uid;
    group = "norish";
    isSystemUser = true;
  };
  users.groups.norish.gid = uid;

  # Started as a non-root user, the entrypoint skips its chown, so the
  # uploads dir must already belong to norish.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root -"
    "d ${dataDir}/uploads 0750 norish norish -"
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
    locations."/api/v1/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      extraConfig = ''
        allow ${dockerBridge};
      '' + tailnetOnly;
    };
  };
}
