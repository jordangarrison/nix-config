{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  mkConfig = extra: (lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs.inputs = flake.inputs;
    modules = [
      ../modules/llm-agents-overlay.nix
      ../modules/nixos/hermes.nix
      {
        system.stateVersion = "25.05";
        services.hermes.user = lib.mkDefault "jordangarrison";
        users.users.jordangarrison.isNormalUser = true;
      }
      extra
    ];
  }).config;
  disabled = mkConfig { };
  enabled = mkConfig {
    services.hermes = {
      enable = true;
      allowedUsers = [ "U0123456789" ];
      desktop.enable = true;
    };
  };
  invalid = users: mkConfig {
    services.hermes = { enable = true; allowedUsers = users; };
  };
  rejects = users: lib.any (a: !a.assertion && lib.hasPrefix "services.hermes." a.message) (invalid users).assertions;
  unit = enabled.systemd.services.hermes-gateway;
  serve = enabled.systemd.services.hermes-serve;
  noDesktop = mkConfig {
    services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; };
  };
  host = flake.nixosConfigurations.endeavour.config;
  remoteServe = host.systemd.services.hermes-serve;
  remoteSettings = builtins.fromJSON host.environment.etc."hermes-service/config.yaml".source.text;
  vhost = host.services.nginx.virtualHosts."hermes.jordangarrison.dev";
  settings = builtins.fromJSON enabled.environment.etc."hermes-service/config.yaml".source.text;
  manifest = builtins.fromJSON (builtins.readFile ../docs/runbooks/hermes-slack-manifest.json);
  unrestrictedUser = service: service.serviceConfig.User == "jordangarrison"
    && lib.all (name: !(builtins.hasAttr name service.serviceConfig)) [
      "NoNewPrivileges" "ProtectSystem" "ProtectHome" "PrivateTmp"
      "PrivateDevices" "ProtectKernelTunables" "ProtectKernelModules"
      "ProtectControlGroups" "RestrictSUIDSGID" "RestrictAddressFamilies"
      "CapabilityBoundingSet"
    ];
  tests = {
    serviceConfigIsProfileLocal = !(enabled.environment.etc ? "hermes/config.yaml")
      && enabled.environment.etc ? "hermes-service/config.yaml";
    disabledHasNoService = !(disabled.systemd.services ? hermes-gateway) && !(disabled.systemd.services ? hermes-serve);
    desktopOptIn = !(noDesktop.systemd.services ? hermes-serve);
    remoteAuthGate = remoteSettings.dashboard.public_url == "https://hermes.jordangarrison.dev";
    pluginsOptIn = settings.plugins.enabled == [ ];
    sharedAgentSkills = (settings.skills.external_dirs or [ ]) == [ "/home/jordangarrison/.agents/skills" ];
    sharedPersonalInstructions = (remoteSettings.agent.system_prompt or "") ==
      builtins.readFile ../users/jordangarrison/agents/AGENTS.md;
    personalInstructionsOptIn = (settings.agent.system_prompt or "") == "";
    serviceLauncherInstalled = lib.any (pkg: lib.getName pkg == "hermes-service") enabled.environment.systemPackages;
    hostConduitEnabled = lib.elem "conduit_push" remoteSettings.plugins.enabled;
    hostHerdrEnabled = lib.elem "herdr-agent-state" remoteSettings.plugins.enabled;
    hostConduitSource = host.services.hermes.plugins ? conduit_push;
    pluginsTriggerRestart = lib.elem host.environment.etc."hermes-service/plugins".source remoteServe.restartTriggers
      && lib.elem host.environment.etc."hermes-service/plugins".source host.systemd.services.hermes-gateway.restartTriggers;
    remoteCredentials = remoteServe.serviceConfig.EnvironmentFile == [ "/var/lib/hermes-secrets/desktop-environment" ]
      && !(remoteServe.environment ? HERMES_DASHBOARD_BASIC_AUTH_PASSWORD);
    remoteProxy = vhost.forceSSL && vhost.useACMEHost == "hermes.jordangarrison.dev"
      && vhost.locations."/".proxyPass == "http://127.0.0.1:9119" && vhost.locations."/".proxyWebsockets;
    remotePrivate = lib.all (text: lib.hasInfix text vhost.locations."/".extraConfig)
      [ "allow 100.64.0.0/10;" "allow fd7a:115c:a1e0::/48;" "deny all;" ];
    remoteNoTicketLogs = lib.hasInfix "access_log off;" vhost.extraConfig;
    remoteTrustedClientIP = !vhost.locations."/".recommendedProxySettings
      && lib.hasInfix "proxy_set_header X-Forwarded-For $remote_addr;" vhost.locations."/".extraConfig;
    desktopBootService = serve.wantedBy == [ "multi-user.target" ];
    desktopSharesIdentity = serve.serviceConfig.User == unit.serviceConfig.User
      && serve.environment.HERMES_HOME == unit.environment.HERMES_HOME;
    desktopNoSlackCredentials = serve.serviceConfig.EnvironmentFile == [ ];
    desktopNotAppOwned = !(serve.environment ? HERMES_DESKTOP) && !(serve.environment ? HERMES_PARENT_PID);
    desktopNoClientDependency = !(lib.elem "graphical-session.target" serve.after);
    desktopOwnerAccess = unrestrictedUser serve && unrestrictedUser remoteServe;
    desktopPortPrivate = !(lib.elem enabled.services.hermes.desktop.port enabled.networking.firewall.allowedTCPPorts);
    hostDesktopInstalled = lib.elem flake.nixosConfigurations.endeavour.pkgs.llm-agents.hermes-desktop
      flake.nixosConfigurations.endeavour.config.home-manager.users.jordangarrison.home.packages;
    opportunityDesktopInstalled = lib.elem flake.nixosConfigurations.opportunity.pkgs.llm-agents.hermes-desktop
      flake.nixosConfigurations.opportunity.config.home-manager.users.jordangarrison.home.packages;
    macbookDesktopInstalled = lib.elem flake.darwinConfigurations.H952L3DPHH.pkgs.llm-agents.hermes-desktop
      flake.darwinConfigurations.H952L3DPHH.config.home-manager.users."jordan.garrison".home.packages;
    hostEnabled = flake.nixosConfigurations.endeavour.config.services.hermes.enable;
    hostCliSharesServiceHome = (host.home-manager.users.jordangarrison.home.shellAliases.hermes or "") == "hermes-service";
    rejectsEmptyAllowlist = rejects [ ];
    rejectsWildcard = rejects [ "*" ];
    rejectsInjectedAllowlist = rejects [ "U123,*" ];
    bootService = unit.wantedBy == [ "multi-user.target" ];
    slackEnrollmentGated = unit.unitConfig.ConditionPathExists == [
      "/home/jordangarrison/.local/share/hermes-service/auth.json"
      "/var/lib/hermes-secrets/environment" "/var/lib/hermes-secrets/enabled"
    ];
    standardDashboard = lib.hasInfix "dashboard --isolated --no-open --skip-build --host 127.0.0.1 --port 9119"
      (builtins.readFile serve.serviceConfig.ExecStart)
      && !(lib.elem "hermes-gateway.service" serve.wants);
    slackOptIn = !settings.platforms.slack.enabled
      && lib.hasInfix "/var/lib/hermes-secrets/enabled" unit.preStart;
    gatewayCredentials = host.systemd.services.hermes-gateway.serviceConfig.EnvironmentFile == [
      "-/run/hermes-service/slack-environment" "/var/lib/hermes-secrets/desktop-environment"
    ];
    ownerIdentity = unit.serviceConfig.User == "jordangarrison" && unit.serviceConfig.Group == "users";
    ownerHomeAccessible = unrestrictedUser unit && unrestrictedUser host.systemd.services.hermes-gateway;
    separateServiceProfile = unit.environment.HOME == "/home/jordangarrison"
      && unit.environment.HERMES_HOME == "/home/jordangarrison/.local/share/hermes-service";
    ownerToolsOnPath = lib.elem "/etc/profiles/per-user/jordangarrison" (map toString unit.path);
    sudoWrapperFirst = lib.all (service: lib.head (map toString service.path) == "/run/wrappers") [ unit serve ];
    privateFiles = unit.serviceConfig.UMask == "0077";
    rootOwnedGate = lib.elem "d /var/lib/hermes-secrets 0700 root root - -" enabled.systemd.tmpfiles.rules;
    runtimeSecrets = unit.serviceConfig.EnvironmentFile == [ "-/run/hermes-service/slack-environment" ];
    managedConfig = unit.environment.HERMES_MANAGED == "nixos";
    restrictedUsers = unit.environment.SLACK_ALLOWED_USERS == "U0123456789"
      && unit.environment.SLACK_ALLOW_ALL_USERS == "false" && unit.environment.GATEWAY_ALLOW_ALL_USERS == "false";
    foregroundSupervised = lib.hasInfix "gateway run --external-supervisor" unit.serviceConfig.ExecStart
      && unit.serviceConfig.Restart == "on-failure";
    oauthNotApiKey = settings.model.provider == "openai-codex" && settings.fallback_providers == [ ];
    independentOAuthGrant = !settings.auth.adopt_external_logins;
    hostDefaultModel = remoteSettings.model.default == "gpt-6.1-sol";
    steerBusyChats = remoteSettings.display.busy_input_mode == "steer";
    codingTools = settings.toolsets == [ "hermes-cli" ] && settings.platform_toolsets.slack == [ "hermes-slack" ]
      && settings.platform_toolsets.cron == [ "hermes-cron" ] && !(settings.agent ? disabled_toolsets);
    localTerminal = settings.terminal.backend == "local" && settings.terminal.cwd == "/home/jordangarrison";
    noPairing = settings.platforms.slack.extra.unauthorized_dm_behavior == "ignore";
    denyChannels = settings.platforms.slack.extra.allowed_channels == [ "DM_ONLY" ];
    noBotLoops = settings.platforms.slack.extra.allow_bots == "none";
    noHttpPlatforms = !settings.platforms.api_server.enabled && !settings.platforms.webhook.enabled;
    socketMode = manifest.settings.socket_mode_enabled;
    dmEventsOnly = manifest.settings.event_subscriptions.bot_events == [ "message.im" "app_home_opened" "app_context_changed" ];
    noChannelScopes = lib.all (scope: !(lib.hasPrefix "channels:" scope || lib.hasPrefix "groups:" scope || lib.hasPrefix "mpim:" scope)) manifest.oauth_config.scopes.bot;
    noWorkspaceSlashCollisions = !(manifest.features ? slash_commands);
  };
in
assert lib.assertMsg (lib.all (result: result) (lib.attrValues tests))
  "Hermes module tests failed: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: result: !result) tests))}";
tests
