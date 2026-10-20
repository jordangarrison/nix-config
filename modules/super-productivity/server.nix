{ config, lib, pkgs, ... }:

# Self-hosted Super Productivity server: the static web app plus a WebDAV
# sync backend on one tailnet-only vhost. The desktop app is app.nix.
#
# The app keeps its data in the browser; WebDAV is only the sync target, so
# desktop/mobile clients can point at the same URL. WebDAV lives on the same
# origin under /webdav/, which avoids the CORS problems the web app has with
# third-party WebDAV servers.
#
# Apache mod_dav rather than hacdias/webdav (services.webdav): Super
# Productivity relies on strong ETags + If-Match for atomic sync-file writes,
# and hacdias ignores If-Match (upstream #10590). Upstream's own E2E server
# is mod_dav with `FileETag Digest` for the same reason.
#
# Server and client setup, including the htpasswd file: README.md.
let
  cfg = config.services.super-productivity;
  inherit (cfg) domain;
  davPort = cfg.webdavPort;
  stateDir = "/var/lib/super-productivity-webdav";
  prefillUser = builtins.head cfg.webdavUsers;

  # Same tailnet boundary as executor and norish. endeavour's host firewall is
  # off, so without this any LAN client sending this Host/SNI gets through.
  tailnetOnly = ''
    allow 127.0.0.1;
    allow ::1;
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    deny all;
  '';

  web = pkgs.callPackage ../../packages/super-productivity-web { };

  # Prefills the sync settings form (what the Docker image's entrypoint
  # generates from WEBDAV_* env vars). Kept outside the web build so editing
  # it doesn't rebuild the Angular app.
  syncDefaults = pkgs.writeTextDir "assets/sync-config-default-override.json"
    (builtins.toJSON {
      syncProvider = "WebDAV";
      webDav = {
        baseUrl = "https://${domain}/webdav/${prefillUser}/";
        userName = prefillUser;
        syncFolderPath = "/";
      };
    });

  webRoot = pkgs.symlinkJoin {
    name = "super-productivity-web-root";
    # First path wins: the build ships a placeholder at the same path.
    paths = [ syncDefaults web ];
  };

  httpdConf = pkgs.writeText "super-productivity-webdav.conf" (''
    ServerRoot ${pkgs.apacheHttpd}
    # Matches the public URL so mod_dav's absolute hrefs line up behind nginx.
    ServerName https://${domain}:443
    UseCanonicalName On
    Listen 127.0.0.1:${toString davPort}
    DefaultRuntimeDir /run/super-productivity-webdav
    PidFile /run/super-productivity-webdav/httpd.pid

    LoadModule mpm_event_module modules/mod_mpm_event.so
    LoadModule unixd_module modules/mod_unixd.so
    LoadModule alias_module modules/mod_alias.so
    LoadModule authn_core_module modules/mod_authn_core.so
    LoadModule authn_file_module modules/mod_authn_file.so
    LoadModule authz_core_module modules/mod_authz_core.so
    LoadModule authz_user_module modules/mod_authz_user.so
    LoadModule auth_basic_module modules/mod_auth_basic.so
    LoadModule dav_module modules/mod_dav.so
    LoadModule dav_fs_module modules/mod_dav_fs.so

    # stderr is the journal socket, which Apache can't reopen by path; pipe
    # through cat, which inherits the service's stdout.
    ErrorLog "|${pkgs.coreutils}/bin/cat"
    LogLevel warn

    DavLockDB ${stateDir}/lock/DavLock
    # Mtime ETags are weak for a second after each write and the app sends no
    # If-Match for weak tags; content digests stay strong.
    FileETag Digest

    DocumentRoot ${pkgs.emptyDirectory}
    <Directory />
      Require all denied
    </Directory>

    # One folder per login: /webdav/<user>/ is open only to <user>, and the
    # shared root is closed, so logins can't read or clobber each other's data.
    # A wrong password is 401; a right password on the wrong folder (e.g. a
    # base URL missing <user>/) is 403.
    Alias /webdav/ ${stateDir}/data/
    <Directory ${stateDir}/data>
      Dav On
      AuthType Basic
      AuthName "Super Productivity"
      AuthBasicProvider file
      AuthUserFile ''${CREDENTIALS_DIRECTORY}/htpasswd
      # Logged in but not allowed here: 403. Apache's default is 401, to
      # invite a different login, which reads as a bad password in the app.
      AuthzSendForbiddenOnFailure On
      # Any login, then refuse: a wrong password still gets 401 here.
      <RequireAll>
        Require valid-user
        Require not valid-user
      </RequireAll>
    </Directory>
  '' + lib.concatMapStrings (user: ''
    <Directory ${stateDir}/data/${user}>
      Require user ${user}
    </Directory>
  '') cfg.webdavUsers);
in
{
  options.services.super-productivity = {
    enable = lib.mkEnableOption "the self-hosted Super Productivity web app and WebDAV sync server";

    domain = lib.mkOption {
      type = lib.types.str;
      # Keep in step with programs.super-productivity.serverUrl's default.
      default = "superproductivity.jordangarrison.dev";
      description = "Public (tailnet) hostname for the nginx vhost and ACME cert.";
    };

    webdavPort = lib.mkOption {
      type = lib.types.port;
      default = 8790;
      description = "Loopback port for the Apache WebDAV backend.";
    };

    webdavUsers = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      default = [ "jordangarrison" ];
      description = ''
        WebDAV logins, each synced to its own /webdav/<user>/ folder. Each
        needs an entry in htpasswdFile. The first is pre-filled in the app's
        sync settings; anyone else edits the URL and username once.
      '';
    };

    htpasswdFile = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/super-productivity-secrets/htpasswd";
      description = "bcrypt htpasswd file for WebDAV basic auth. Kept out of the store; the unit is skipped until it exists.";
    };
  };

  config = lib.mkIf cfg.enable {
  users.users.super-productivity = {
    isSystemUser = true;
    group = "super-productivity";
  };
  users.groups.super-productivity = { };

  systemd.tmpfiles.rules = [
    "d ${stateDir}/data 0750 super-productivity super-productivity -"
    "d ${stateDir}/lock 0750 super-productivity super-productivity -"
  ] ++ map (user: "d ${stateDir}/data/${user} 0750 super-productivity super-productivity -")
    cfg.webdavUsers;

  systemd.services.super-productivity-webdav = {
    description = "Super Productivity WebDAV sync (Apache mod_dav)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = cfg.htpasswdFile;
    serviceConfig = {
      ExecStart = "${pkgs.apacheHttpd}/bin/httpd -f ${httpdConf} -DFOREGROUND";
      ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      User = "super-productivity";
      Group = "super-productivity";
      LoadCredential = "htpasswd:${cfg.htpasswdFile}";
      StateDirectory = "super-productivity-webdav";
      StateDirectoryMode = "0750";
      RuntimeDirectory = "super-productivity-webdav";
      Restart = "on-failure";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };

  # ACME certificate via Cloudflare DNS-01 (defaults from nginx.nix)
  security.acme.certs.${domain} = {
    group = "nginx";
    # The system resolver (Tailscale -> blocky) caches the challenge record's
    # NXDOMAIN, so lego's propagation check times out. Check via Cloudflare.
    dnsResolver = "1.1.1.1:53";
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = domain;
    root = webRoot;
    # Server-level, so every location below inherits it.
    extraConfig = tailnetOnly;

    locations."/" = {
      tryFiles = "$uri $uri/ /index.html";
    };

    # Let the Angular service worker pick up new builds promptly.
    locations."~ ^/(index\\.html|ngsw\\.json|ngsw-worker\\.js)$" = {
      extraConfig = ''
        add_header Cache-Control "no-cache";
      '';
    };

    locations."/webdav/" = {
      proxyPass = "http://127.0.0.1:${toString davPort}";
      extraConfig = ''
        # nginx gzip downgrades ETags to weak, which disables the app's
        # If-Match protection.
        gzip off;
        client_max_body_size 200m;
        proxy_request_buffering off;
      '';
    };
  };
  };
}
