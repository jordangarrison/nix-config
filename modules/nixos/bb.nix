{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.bb;
  providerPackages = {
    cursor = "cursor-agent";
    codex = "codex";
    pi = "pi";
    claude = "claude-code";
  };
  enabledProviders = lib.mapAttrsToList (name: _: cfg.providers.${name}.package) (
    lib.filterAttrs (name: _: cfg.providers.${name}.enable) providerPackages
  );
  isHost = cfg.role == "host";
  # One trailing slash is a valid origin, but concatenating it with /install.sh
  # requests //install.sh, which serves the web app instead of the installer.
  normalizedServerUrl =
    if cfg.serverUrl == null then null else lib.removeSuffix "/" cfg.serverUrl;
  # Match URL.host, then the installer's directory sanitizer.
  sanitizeServerHost = url:
    let
      stripped = lib.removeSuffix "/" (
        lib.removePrefix "http://" (lib.removePrefix "https://" url)
      );
      hostPort = lib.head (lib.splitString "/" stripped);
      host =
        if lib.hasPrefix "https://" url && lib.hasSuffix ":443" hostPort then
          lib.removeSuffix ":443" hostPort
        else if lib.hasPrefix "http://" url && lib.hasSuffix ":80" hostPort then
          lib.removeSuffix ":80" hostPort
        else
          hostPort;
    in
    lib.stringAsChars (
      c: if builtins.match "[0-9A-Za-z.-]" c == null then "-" else c
    ) host;
  parseEnrollmentLine = pkgs.writeText "bb-parse-enrollment-line.js" ''
    const fs = require("node:fs");
    const line = fs.readFileSync(0, "utf8").replace(/\n$/, "");
    const prefix = "export BB_ENROLLMENT=";
    if (!line.startsWith(prefix) || line[prefix.length] !== "'" || !line.endsWith("'")) {
      process.stderr.write("Enrollment response was not a bootstrap bundle.\n");
      process.exit(1);
    }
    const value = line.slice(prefix.length + 1, -1).replaceAll(`'"'"'`, "'");
    JSON.parse(value);
    process.stdout.write(value);
  '';
  bbHostEnroll = pkgs.writeShellScriptBin "bb-host-enroll" ''
    set -eu
    if [ "$(id -u)" -eq 0 ]; then
      echo "Run bb-host-enroll as ${cfg.user}, not root." >&2
      exit 1
    fi
    if [ "$(id -un)" != ${lib.escapeShellArg cfg.user} ]; then
      echo "Run bb-host-enroll as ${cfg.user}." >&2
      exit 1
    fi
    token=''${1:-}
    if [ -z "$token" ]; then
      echo "Usage: bb-host-enroll <enrollment-token>" >&2
      echo "On the bb server, run: bb machine create --provider manual" >&2
      echo "Pass the X-BB-Enrollment value from that command." >&2
      exit 2
    fi
    bundle=$(${lib.getExe' pkgs.coreutils "mktemp"})
    response=$(${lib.getExe' pkgs.coreutils "mktemp"})
    trap 'rm -f "$bundle" "$response"' EXIT
    if ! ${lib.getExe pkgs.curl} --silent --show-error --fail-with-body \
      -H "X-BB-Enrollment: $token" \
      ${lib.escapeShellArg "${normalizedServerUrl}/install.sh"} \
      -o "$response"; then
      echo "Could not download an enrollment bundle. The token may be used or expired." >&2
      exit 1
    fi
    ${lib.getExe' pkgs.coreutils "head"} -n 1 "$response" \
      | ${lib.getExe pkgs.nodejs} ${parseEnrollmentLine} > "$bundle"
    PATH=${lib.escapeShellArg (lib.makeBinPath [ cfg.package ])}:$PATH \
      BB_DATA_DIR=${lib.escapeShellArg cfg.dataDir} \
      ${lib.getExe' cfg.package "bb"} machine enroll --bootstrap-file "$bundle"
    rm -f "$bundle"
    echo "Enrolled ${cfg.dataDir}."
    if ! systemctl start bb; then
      echo "Start the daemon with: sudo systemctl start bb" >&2
      exit 1
    fi
    echo "Host daemon started."
  '';
in
{
  options.services.bb = {
    enable = lib.mkEnableOption "bb agentic IDE server, or a host daemon connected to one";

    role = lib.mkOption {
      type = lib.types.enum [ "server" "host" ];
      default = "server";
      description = ''
        server runs bb-app, which supervises the API and the local host daemon.
        host runs only the Nix-packaged bb-host-daemon and connects to serverUrl.
      '';
    };

    serverUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://bb.jordangarrison.dev";
      description = ''
        bb server origin for role = "host". The daemon enrolls against this URL.
        Leave unset when role = "server".
      '';
    };

    package = lib.mkPackageOption pkgs [ "llm-agents" "bb-app" ] { };

    user = lib.mkOption {
      type = lib.types.str;
      example = "jordangarrison";
      description = "Existing NixOS user running bb and its coding agents. No account is created.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = config.users.users.${cfg.user}.group;
      defaultText = lib.literalExpression "config.users.users.<user>.group";
      description = "Primary group of the bb service.";
    };

    home = lib.mkOption {
      type = lib.types.path;
      default = config.users.users.${cfg.user}.home;
      defaultText = lib.literalExpression "config.users.users.<user>.home";
      description = "HOME used for repositories, Git/SSH and native provider configuration/credentials.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default =
        if cfg.role == "host" && cfg.serverUrl != null then
          "${cfg.home}/.bb-machines/${sanitizeServerHost cfg.serverUrl}"
        else
          "${cfg.home}/.bb";
      defaultText = lib.literalExpression ''
        if role == "host" then "''${home}/.bb-machines/<server-host>" else "''${home}/.bb"
      '';
      description = ''
        Mutable bb state directory, created with mode 0700.
        A host daemon must not use ~/.bb; that directory belongs to a local server
        or the desktop app.
      '';
    };

    hostDaemonPort = lib.mkOption {
      type = lib.types.port;
      default = 38887;
      description = ''
        Loopback port for a role = "host" daemon. The server role chooses its own
        daemon port inside bb-app.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 38886;
      description = "bb web UI/API TCP port.";
    };

    bindHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Web UI/API bind address. Keep loopback for a separate Tailscale Serve proxy.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the web UI/API TCP port in the host firewall.";
    };

    providers = lib.mapAttrs (name: packageName: {
      enable = lib.mkEnableOption "the ${name} executable on bb's PATH";
      package = lib.mkPackageOption pkgs [ "llm-agents" packageName ] { };
    }) providerPackages;

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "with pkgs; [ nodejs ripgrep ]";
      description = "Additional providers and development tools available to bb and its child processes.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret environment variables. Values are stored in the Nix store; use environmentFile for secrets.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/bb";
      description = ''
        Absolute runtime path to a systemd EnvironmentFile containing credentials.
        Use a quoted string, not a Nix path literal; the file must not enter the
        Nix store. It must exist before bb starts (systemd reads it as root).
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional bb-app start arguments. Do not override module-managed flags or enable self-updates.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          arg:
          !(lib.elem arg [
            "--in-app-updates"
            "--auto-update"
          ])
        ) cfg.extraArgs;
        message = "services.bb: in-app/host-daemon updates must remain disabled; update the llm-agents flake input instead.";
      }
      {
        assertion = cfg.environmentFile == null || lib.hasPrefix "/" cfg.environmentFile;
        message = "services.bb.environmentFile must be an absolute runtime path.";
      }
      {
        assertion = cfg.role == "server" || cfg.serverUrl != null;
        message = "services.bb.serverUrl is required when role is host.";
      }
      {
        assertion = cfg.role == "host" || cfg.serverUrl == null;
        message = "services.bb.serverUrl applies only when role is host.";
      }
      {
        assertion =
          cfg.serverUrl == null
          || builtins.match "https?://[0-9A-Za-z.-]+(:[0-9]+)?/?" cfg.serverUrl != null;
        message = "services.bb.serverUrl must be an http(s) origin without a path, query, or credentials.";
      }
      {
        assertion = cfg.role == "server" || cfg.dataDir != "${cfg.home}/.bb";
        message = "services.bb role host cannot use ~/.bb; that directory belongs to a local server or the desktop app.";
      }
      {
        assertion = cfg.role == "server" || !cfg.openFirewall;
        message = "services.bb.openFirewall applies to the server role; a host daemon listens on loopback only.";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.openFirewall && cfg.role == "server") [ cfg.port ];

    environment.systemPackages = lib.mkIf (isHost && cfg.serverUrl != null) [ bbHostEnroll ];

    systemd.tmpfiles.settings."10-bb" = {
      ${cfg.dataDir}.d = {
        mode = "0700";
        user = cfg.user;
        group = cfg.group;
      };
    } // lib.optionalAttrs (isHost && lib.hasPrefix "${cfg.home}/.bb-machines/" cfg.dataDir) {
      # Implicit parents are created root-owned by tmpfiles. Enrollment runs
      # as the user and must be able to create per-server directories here.
      "${cfg.home}/.bb-machines".d = {
        mode = "0700";
        user = cfg.user;
        group = cfg.group;
      };
    };

    systemd.services.bb = {
      description = if isHost then "bb host daemon" else "bb agentic IDE";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig = {
        RequiresMountsFor = utils.escapeSystemdExecArgs [
          cfg.home
          cfg.dataDir
        ];
      }
      // lib.optionalAttrs isHost {
        # Stay stopped until bb-host-enroll writes auth.json.
        ConditionPathExists = "${cfg.dataDir}/auth.json";
      };

      # Keep declared providers first, but also expose the user's installed
      # tools. bb's daemon probes a login shell for PATH; NixOS's shell init
      # would otherwise replace this PATH with the global profile list.
      path =
        enabledProviders
        ++ cfg.extraPackages
        ++ [
          cfg.package
          pkgs.git
          pkgs.openssh
          pkgs.bash
          "/run/wrappers"
          "/etc/profiles/per-user/${cfg.user}"
          "${cfg.home}/.nix-profile"
          "/run/current-system/sw"
        ];
      environment = cfg.environment // {
        HOME = cfg.home;
        __NIXOS_SET_ENVIRONMENT_DONE = "1";
        BB_HOST_DAEMON_AUTO_UPDATE = "0";
      };

      # Intentionally not sandboxed: bb must access the user's worktrees,
      # credentials and development tools, and spawn interactive agents.
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.home;
        ExecStart = utils.escapeSystemdExecArgs (
          (
            if isHost then
              [
                (lib.getExe' cfg.package "bb-host-daemon")
                "--data-dir"
                cfg.dataDir
                "--host-daemon-port"
                (toString cfg.hostDaemonPort)
              ]
              ++ lib.optionals (normalizedServerUrl != null) [
                "--server-url"
                normalizedServerUrl
              ]
            else
              [
                (lib.getExe cfg.package)
                "start"
                "--bundled"
                "--data-dir"
                cfg.dataDir
                "--server-port"
                (toString cfg.port)
                "--server-bind-host"
                cfg.bindHost
              ]
          )
          ++ cfg.extraArgs
        );
        Restart = "on-failure";
        RestartSec = "5s";
        # Stop the whole process tree, including coding agents.
        KillMode = "control-group";
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
