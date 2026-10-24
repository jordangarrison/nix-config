{ config, lib, pkgs, ... }:

# Personal always-on coding agent; system services run as the configured user.
# Setup and activation gates: docs/runbooks/hermes.md.
let
  cfg = config.services.hermes;
  package = pkgs.llm-agents.hermes-agent;
  userHome = config.users.users.${cfg.user}.home;
  group = config.users.users.${cfg.user}.group;
  home = "${userHome}/.local/share/hermes-service";
  secrets = "/var/lib/hermes-secrets";
  # Extract the integration shipped by the pinned Herdr binary in an isolated
  # build home. Its installer must never rewrite our live Nix-owned config.
  herdrPlugin = pkgs.runCommand "hermes-herdr-plugin" { } ''
    export HOME="$TMPDIR/home"
    export HERMES_HOME="$HOME/hermes"
    mkdir -p "$HERMES_HOME"
    ${pkgs.llm-agents.herdr}/bin/herdr integration install hermes
    mkdir -p "$out"
    cp -r "$HERMES_HOME/plugins/herdr-agent-state/." "$out/"
  '';
  pluginTree = pkgs.linkFarm "hermes-plugins"
    (lib.mapAttrsToList (name: path: { inherit name path; }) cfg.plugins);
  settings = {
    plugins.enabled = lib.attrNames cfg.plugins;
    # Reuse Home Manager's cross-agent skills without copying them into the
    # writable Hermes profile. Store-backed skills stay immutable; repo-backed
    # skills retain the shared checkout's normal edit permissions.
    skills.external_dirs = [ "${userHome}/.agents/skills" ];
    model = {
      provider = "openai-codex";
      default = cfg.model;
    };
    # A dedicated OAuth grant; never adopt the operator's Codex/other logins.
    auth.adopt_external_logins = false;
    fallback_providers = [ ];
    display.busy_input_mode = "steer";
    agent = {
      reasoning_effort = "medium";
      system_prompt = cfg.instructions;
    };
    # Upstream full tool bundles: coding, terminal, files, skills, delegation,
    # and the normal available integrations. Plugin tools remain available.
    toolsets = [ "hermes-cli" ];
    platform_toolsets = {
      cli = [ "hermes-cli" ];
      slack = [ "hermes-slack" ];
      cron = [ "hermes-cron" ];
    };
    terminal = { backend = "local"; cwd = userHome; };
    mcp_servers = { };
    gateway = {
      allow_all_users = false;
      unauthorized_dm_behavior = "ignore";
      multiplex_profiles = false;
    };
    platforms = {
      slack = {
        enabled = false;
        extra = {
          unauthorized_dm_behavior = "ignore";
          # Empty means ALL channels in Hermes. A non-channel sentinel denies
          # every channel/group DM; authorized 1:1 DMs are exempt upstream.
          allowed_channels = [ "DM_ONLY" ];
          require_mention = true;
          allow_bots = "none";
          reactions = false;
        };
      };
      api_server.enabled = false;
      webhook.enabled = false;
    };
    stt_enabled = false;
  } // lib.optionalAttrs (cfg.desktop.publicHost != null) {
    # Enables upstream's real remote-auth gate even on a loopback listener.
    # Host/Origin checks also trust exactly this reverse-proxy hostname.
    dashboard.public_url = "https://${cfg.desktop.publicHost}";
  };
  # JSON is valid YAML; no generator dependency and no secrets in this file.
  configFile = pkgs.writeText "hermes-config.yaml" (builtins.toJSON settings);
  slackConfigFile = pkgs.writeText "hermes-slack-config.yaml" (builtins.toJSON
    (lib.recursiveUpdate settings { platforms.slack.enabled = true; }));
  # A separate command selects the service profile without redirecting bare
  # hermes or changing cwd. It does not load root-owned service secrets.
  cliLauncher = pkgs.runCommand "hermes-service" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p "$out/bin"
    makeWrapper ${package}/bin/hermes "$out/bin/hermes-service" \
      --set HERMES_HOME ${lib.escapeShellArg home} \
      --set HERMES_MANAGED nixos
  '';
  # Run the published dashboard, not the canonical gateway API or headless
  # `serve`. A stable local token is separate from provider OAuth, generated
  # privately on first service start; never printed or stored in a derivation.
  serveLauncher = pkgs.writeShellScript "hermes-serve" ''
    set -euo pipefail
    ${lib.optionalString (cfg.desktop.publicHost != null) ''
      # Remote auth must never fall back to the local session-token scheme.
      : "''${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:?Missing dashboard username}"
      : "''${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:?Missing dashboard password}"
      : "''${HERMES_DASHBOARD_BASIC_AUTH_SECRET:?Missing dashboard signing secret}"
      unset HERMES_DASHBOARD_SESSION_TOKEN
      exec ${package}/bin/hermes dashboard --isolated --no-open --skip-build --host 127.0.0.1 --port ${toString cfg.desktop.port}
    ''}
    umask 077
    runtime_home="''${HERMES_HOME:-${home}}"
    token_file="$runtime_home/desktop-session-token"
    if [[ ! -e "$token_file" ]]; then
      tmp=$(${pkgs.coreutils}/bin/mktemp "$runtime_home/.desktop-token.XXXXXX")
      trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
      ${pkgs.openssl}/bin/openssl rand -hex 32 > "$tmp"
      ${pkgs.coreutils}/bin/mv "$tmp" "$token_file"
      trap - EXIT
    fi
    token=$(< "$token_file")
    if [[ ! "$token" =~ ^[0-9a-f]{64}$ ]]; then
      echo "Invalid Desktop session token file; refusing to start." >&2
      exit 1
    fi
    export HERMES_DASHBOARD_SESSION_TOKEN="$token"
    exec ${package}/bin/hermes dashboard --isolated --no-open --skip-build --host 127.0.0.1 --port ${toString cfg.desktop.port}
  '';
  # The two system services share state, but neither is a child of Desktop.
  # Use the owner's normal permissions, including existing sudo policy.
  # No service sandbox: this is the user's coding/admin agent.
  userService = {
    Type = "simple";
    User = cfg.user;
    Group = group;
    WorkingDirectory = userHome;
    Restart = "on-failure";
    RestartSec = "15s";
    UMask = "0077";
  };
  serviceEnv = {
    HOME = userHome;
    HERMES_HOME = home;
    HERMES_MANAGED = "nixos";
    SLACK_ALLOWED_USERS = lib.concatStringsSep "," cfg.allowedUsers;
    SLACK_ALLOW_ALL_USERS = "false";
    GATEWAY_ALLOW_ALL_USERS = "false";
    PYTHONUNBUFFERED = "1";
  };
in
{
  options.services.hermes = {
    enable = lib.mkEnableOption "personal always-on Hermes coding agent";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing normal user that owns Hermes and its coding processes.";
    };
    instructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shared personal instructions appended by Hermes across CLI, Desktop, and messaging sessions.";
    };
    herdrIntegration.enable = lib.mkEnableOption "the pinned Herdr session-reporting plugin in the service profile";
    plugins = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = ''
        Native Hermes plugin sources, keyed by manifest name. Sources must be
        pinned derivations with plugin.yaml and __init__.py at their root.
        Nix installs and enables them; runtime state stays in HERMES_HOME.
        Plugins execute trusted service code, not sandboxed model tools.
      '';
    };
    desktop = {
      enable = lib.mkEnableOption "systemd-owned Hermes web dashboard and Desktop backend on localhost";
      publicHost = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "[a-z0-9][a-z0-9.-]*[.][a-z]+");
        default = null;
        description = ''
          HTTPS reverse-proxy hostname; null keeps localhost session-token auth.
          Requires a separately configured trusted proxy and root-owned
          /var/lib/hermes-secrets/desktop-environment with the dashboard
          username, password, and persistent signing secret. Never a Nix secret.
        '';
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 9119;
        description = "Loopback-only Desktop backend port. No firewall port is opened.";
      };
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "gpt-6.1-sol";
      description = "Default Codex OAuth model; verify availability in the enrolled account catalog.";
    };
    allowedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Slack member IDs allowed to DM this bot. Wildcards and empty allowlists are rejected.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.hermes.plugins = lib.mkIf cfg.herdrIntegration.enable {
      herdr-agent-state = herdrPlugin;
    };
    assertions = [{
      assertion = cfg.allowedUsers != [ ] && lib.all (id: builtins.match "[UW][A-Z0-9]+" id != null) cfg.allowedUsers;
      message = "services.hermes.allowedUsers must contain explicit Slack member IDs.";
    } {
      assertion = lib.all (name: builtins.match "[A-Za-z0-9_-]+" name != null) (lib.attrNames cfg.plugins);
      message = "services.hermes.plugins keys must be simple plugin names, not paths.";
    }];

    environment.systemPackages = [ package cliLauncher ];
    # /etc/hermes is upstream's host-wide admin overlay, not a profile home.
    # Keep this service's settings out of unrelated CLI/Desktop profiles.
    environment.etc."hermes-service/config.yaml".source = configFile;
    environment.etc."hermes-service/plugins".source = pluginTree;
    environment.etc."hermes-service/slack-manifest.json".source = ../../docs/runbooks/hermes-slack-manifest.json;

    # Managed Hermes expects these directories before its first CLI invocation.
    # OAuth refresh state must remain writable; config stays Nix-owned.
    systemd.tmpfiles.rules = [
      "d ${secrets} 0700 root root - -"
      # Root-owned selection prevents the user from redirecting privileged
      # setup writes; the non-secret config stays available when owner is down.
      "d /run/hermes-service 0711 root root - -"
      "L+ /run/hermes-service/config.yaml - - - - ${configFile}"
      "L+ ${home}/config.yaml - - - - /run/hermes-service/config.yaml"
    ] ++ map (dir: "d ${home}${dir} 0700 ${cfg.user} ${group} - -") [
      "" "/cron" "/sessions" "/logs" "/memories" "/skills" "/plugins"
    ] ++ lib.mapAttrsToList (name: _: "L+ ${home}/plugins/${name} - - - - ${pluginTree}/${name}") cfg.plugins;

    systemd.services.hermes-gateway = {
      description = "Hermes opt-in Slack gateway";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # No always-on canonical owner. This unit connects Slack only after
      # explicit enrollment, and is not a dependency of the web dashboard.
      unitConfig.ConditionPathExists = [ "${home}/auth.json" "${secrets}/environment" "${secrets}/enabled" ];
      # Never read/copy Slack credentials before explicit root-owned opt-in.
      preStart = ''
        set -euo pipefail
        rm -f /run/hermes-service/slack-environment
        ln -sfn ${configFile} /run/hermes-service/config.yaml
        if test -e ${home}/auth.json && test -f ${secrets}/environment && test -f ${secrets}/enabled; then
          install -m 600 -o root -g root ${secrets}/environment /run/hermes-service/slack-environment
          ln -sfn ${slackConfigFile} /run/hermes-service/config.yaml
        fi
      '';
      restartTriggers = [ configFile pluginTree ];
      environment = serviceEnv;
      path = [ "/run/wrappers" pkgs.coreutils pkgs.git pkgs.bash pkgs.systemd "/run/current-system/sw" "/etc/profiles/per-user/${cfg.user}" ];
      serviceConfig = userService // {
        ExecStartPre = lib.mkForce [ ("+" + pkgs.writeShellScript "hermes-prepare" config.systemd.services.hermes-gateway.preStart) ];
        EnvironmentFile = [ "-/run/hermes-service/slack-environment" ]
          ++ lib.optional (cfg.desktop.publicHost != null) "${secrets}/desktop-environment";
        ExecStart = "${package}/bin/hermes gateway run --external-supervisor";
      };
    };

    systemd.services.hermes-serve = lib.mkIf cfg.desktop.enable {
      description = "Hermes standard web dashboard";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      restartTriggers = [ configFile pluginTree ];
      environment = serviceEnv;
      path = [ "/run/wrappers" pkgs.coreutils pkgs.git pkgs.bash pkgs.systemd "/run/current-system/sw" "/etc/profiles/per-user/${cfg.user}" ];
      # No Slack credentials and no Desktop-owner PID/nonce: this is a resident
      # backend, not Desktop's auto-spawned runtime or a second Slack dispatcher.
      serviceConfig = userService // {
        EnvironmentFile = lib.optional (cfg.desktop.publicHost != null) "${secrets}/desktop-environment";
        ExecStart = toString serveLauncher;
      };
    };
  };
}
