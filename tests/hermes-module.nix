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
  rejectsProfiles = profiles: lib.any (a: !a.assertion && lib.hasPrefix "services.hermes.profiles" a.message) (mkConfig {
    services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; mcpServers.known.url = "https://example.invalid/mcp"; inherit profiles; };
  }).assertions;
  unit = enabled.systemd.services.hermes-gateway;
  serve = enabled.systemd.services.hermes-serve;
  noDesktop = mkConfig {
    services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; };
  };
  host = flake.nixosConfigurations.endeavour.config;
  remoteServe = host.systemd.services.hermes-serve;
  # Store paths (stdio MCP commands) carry context fromJSON rejects; the test only reads values.
  remoteSettings = builtins.fromJSON (builtins.unsafeDiscardStringContext host.environment.etc."hermes-service/config.yaml".source.text);
  vhost = host.services.nginx.virtualHosts."hermes.jordangarrison.dev";
  hostGateway = host.systemd.services.hermes-gateway;
  rejectsMarker = marker: lib.any (a: !a.assertion && lib.hasPrefix "services.hermes.slack" a.message) (mkConfig {
    services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; slack.enableMarker = marker; };
  }).assertions;
  specOf = cfg: builtins.fromJSON (builtins.unsafeDiscardStringContext cfg.environment.etc."hermes-service/profiles.json".source.text);
  hostSpec = specOf host;
  hostPinned = hostSpec.profiles.default.settings;
  hostSlack = remoteSettings.platforms.slack;
  profilesUnit = host.systemd.services.hermes-profiles;
  hermesUnits = cfg: lib.filterAttrs (name: _: lib.hasPrefix "hermes-" name) cfg.systemd.services;
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
    sharedMcpServers = remoteSettings.mcp_servers.executor == { url = "https://executor.jordangarrison.dev/mcp"; auth = "oauth"; }
      && remoteSettings.mcp_servers ? executor-flo;
    # Hermes owns the live config; Nix seeds it once and pins a few leaves.
    configHermesOwned = lib.all (unit: !(unit.environment ? HERMES_MANAGED)) (lib.attrValues (hermesUnits host))
      && !lib.any (rule: lib.hasInfix "config.yaml" rule) host.systemd.tmpfiles.rules
      && !lib.hasInfix "HERMES_MANAGED" (lib.findFirst (pkg: lib.getName pkg == "hermes-service")
        (throw "launcher missing") host.environment.systemPackages).buildCommand;
    seedIsReferenceConfig = hostSpec.profiles.default.seed == remoteSettings
      && hostSpec.home == "/home/jordangarrison/.local/share/hermes-service";
    pinsRepoOwnedSettings = hostPinned.mcp_servers == remoteSettings.mcp_servers
      && hostPinned.skills.external_dirs == [ "/home/jordangarrison/.agents/skills" ]
      && hostPinned.agent.system_prompt == builtins.readFile ../users/jordangarrison/agents/AGENTS.md
      && hostPinned.dashboard.public_url == "https://hermes.jordangarrison.dev"
      && !hostPinned.auth.adopt_external_logins
      && lib.attrNames hostPinned == [ "agent" "auth" "dashboard" "mcp_servers" "skills" ];
    # Pin changes restart the services; seed-only changes never touch the live config.
    pinsRestartServices = lib.all (unit: lib.elem host.environment.etc."hermes-service/pinned.json".source unit.restartTriggers)
      [ remoteServe hostGateway ]
      && !(lib.elem host.environment.etc."hermes-service/config.yaml".source remoteServe.restartTriggers);
    profilesBeforeServices = lib.all (u: lib.elem u profilesUnit.before) [ "hermes-serve.service" "hermes-gateway.service" ]
      && profilesUnit.wantedBy == [ "multi-user.target" ];
    profilesRunAsOwner = profilesUnit.serviceConfig.User == "jordangarrison" && profilesUnit.serviceConfig.Type == "oneshot"
      && profilesUnit.serviceConfig.RemainAfterExit && profilesUnit.serviceConfig.UMask == "0077";
    # A single default bot: no named profiles, so no routes or shared token links.
    hostSingleProfile = lib.attrNames hostSpec.profiles == [ "default" ] && !(remoteSettings.gateway ? profile_routes)
      && !(remoteSettings.gateway ? multiplex_profiles);
    moduleSeedsNamedProfilesPinsOnly = let spec = specOf (mkConfig {
      services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; mcpServers.known.url = "https://example.invalid/mcp";
        profiles.bot = { mcpServers = [ "known" ]; shareMcpTokens = true; }; };
    }); in spec.profiles.bot == { settings.mcp_servers.known.url = "https://example.invalid/mcp"; seed = null; shareMcpTokens = true; };
    # JordanBot's first Slack settings: any channel it is in, Jordan only, follow mentioned threads.
    hostSlackSeed = hostSlack.enabled && hostSlack.extra.allowed_channels == [ ]
      && hostSlack.extra.require_mention && !hostSlack.extra.strict_mention && !hostSlack.extra.thread_require_mention
      && hostSlack.extra.reaction_triggers == [ "jordanbot" ] && hostSlack.extra.reactions && hostSlack.extra.rich_blocks
      && hostSlack.extra.allow_bots == "none" && hostSlack.extra.unauthorized_dm_behavior == "ignore"
      && hostSlack.home_channel.chat_id == "D0CCDQ1JBNY"
      && remoteSettings.display.platforms.slack.memory_notifications == "off" && !remoteSettings.gateway.allow_all_users;
    hostSlackJordanOnly = hostGateway.environment.SLACK_ALLOWED_USERS == "UQ69UGHKM"
      && hostGateway.environment.SLACK_ALLOW_ALL_USERS == "false" && hostGateway.environment.GATEWAY_ALLOW_ALL_USERS == "false";
    hostJordanBotGate = hostGateway.unitConfig.ConditionPathExists == [
      "/home/jordangarrison/.local/share/hermes-service/auth.json" "/var/lib/hermes-secrets/jordanbot-enabled"
    ];
    # Tokens live in the Hermes-owned .env: no unit loads a Slack credential file, and none is in Nix.
    noSlackSecretsInNix = lib.all (unit: lib.all (file: !lib.hasInfix "slack" file && !lib.hasInfix "jordanbot" file)
        (lib.toList (unit.serviceConfig.EnvironmentFile or [ ]))) (lib.attrValues (hermesUnits host))
      && !lib.hasInfix "xoxb-" (builtins.toJSON remoteSettings) && !lib.hasInfix "xapp-" (builtins.toJSON remoteSettings);
    ownerRestartsGatewayOnly = lib.hasInfix ''subject.user == "jordangarrison"'' host.security.polkit.extraConfig
      && lib.hasInfix ''action.lookup("unit") == "hermes-gateway.service"'' host.security.polkit.extraConfig
      && !lib.hasInfix "hermes-serve" host.security.polkit.extraConfig && host.security.polkit.enable;
    defaultSlackDmOnly = settings.platforms.slack.extra.allowed_channels == [ "DM_ONLY" ] && !settings.platforms.slack.enabled;
    rejectsMarkerOutsideSecretDir = rejectsMarker "/home/jordangarrison/enabled";
    rejectsNestedMarker = rejectsMarker "/var/lib/hermes-secrets/../enabled";
    acceptsMarkerInSecretDir = !(rejectsMarker "/var/lib/hermes-secrets/jordanbot-enabled");
    rejectsUnknownProfileServer = rejectsProfiles { bot.mcpServers = [ "missing" ]; };
    rejectsPathProfileName = rejectsProfiles { "../bot".mcpServers = [ "known" ]; };
    rejectsDefaultProfileName = rejectsProfiles { default.shareMcpTokens = true; };
    acceptsKnownProfileServer = !(rejectsProfiles { bot.mcpServers = [ "known" ]; });
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
      "/home/jordangarrison/.local/share/hermes-service/auth.json" "/var/lib/hermes-secrets/enabled"
    ];
    standardDashboard = lib.hasInfix "dashboard --isolated --no-open --skip-build --host 127.0.0.1 --port 9119"
      (builtins.readFile serve.serviceConfig.ExecStart)
      && !(lib.elem "hermes-gateway.service" serve.wants);
    gatewayCredentials = hostGateway.serviceConfig.EnvironmentFile == [ "/var/lib/hermes-secrets/desktop-environment" ];
    ownerIdentity = unit.serviceConfig.User == "jordangarrison" && unit.serviceConfig.Group == "users";
    ownerHomeAccessible = unrestrictedUser unit && unrestrictedUser host.systemd.services.hermes-gateway;
    separateServiceProfile = unit.environment.HOME == "/home/jordangarrison"
      && unit.environment.HERMES_HOME == "/home/jordangarrison/.local/share/hermes-service";
    ownerToolsOnPath = lib.elem "/etc/profiles/per-user/jordangarrison" (map toString unit.path);
    sudoWrapperFirst = lib.all (service: lib.head (map toString service.path) == "/run/wrappers") [ unit serve ];
    privateFiles = unit.serviceConfig.UMask == "0077";
    rootOwnedGate = lib.elem "d /var/lib/hermes-secrets 0700 root root - -" enabled.systemd.tmpfiles.rules;
    runtimeSecrets = unit.serviceConfig.EnvironmentFile == [ ];
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
