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
  opportunity = flake.nixosConfigurations.opportunity.config;
  macbook = flake.darwinConfigurations.H952L3DPHH.config;
  rejectsMarker = marker: lib.any (a: !a.assertion && lib.hasPrefix "services.hermes.slack" a.message) (mkConfig {
    services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; slack.enableMarker = marker; };
  }).assertions;
  specOf = cfg: builtins.fromJSON (builtins.unsafeDiscardStringContext cfg.environment.etc."hermes-service/profiles.json".source.text);
  desktopInstalled = pkgs: cfg: user: lib.elem pkgs.llm-agents.hermes-desktop cfg.home-manager.users.${user}.home.packages;
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
    # Hosts no longer deploy Hermes. The module tests above still cover an enabled fixture.
    hostNotDeployed = !host.services.hermes.enable
      && !(host.systemd.services ? hermes-gateway)
      && !(host.systemd.services ? hermes-serve)
      && !(host.systemd.services ? hermes-profiles)
      && !(host.services.nginx.virtualHosts ? "hermes.jordangarrison.dev")
      && (host.home-manager.users.jordangarrison.home.shellAliases.hermes or "") != "hermes-service"
      && !(desktopInstalled flake.nixosConfigurations.endeavour.pkgs host "jordangarrison")
      && !(desktopInstalled flake.nixosConfigurations.opportunity.pkgs opportunity "jordangarrison")
      && !(desktopInstalled flake.darwinConfigurations.H952L3DPHH.pkgs macbook "jordan.garrison");
    moduleSeedsNamedProfilesPinsOnly = let spec = specOf (mkConfig {
      services.hermes = { enable = true; allowedUsers = [ "U0123456789" ]; mcpServers.known.url = "https://example.invalid/mcp";
        profiles.bot = { mcpServers = [ "known" ]; shareMcpTokens = true; }; };
    }); in spec.profiles.bot == { settings.mcp_servers.known.url = "https://example.invalid/mcp"; seed = null; shareMcpTokens = true; };
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
    personalInstructionsOptIn = (settings.agent.system_prompt or "") == "";
    serviceLauncherInstalled = lib.any (pkg: lib.getName pkg == "hermes-service") enabled.environment.systemPackages;
    desktopBootService = serve.wantedBy == [ "multi-user.target" ];
    desktopSharesIdentity = serve.serviceConfig.User == unit.serviceConfig.User
      && serve.environment.HERMES_HOME == unit.environment.HERMES_HOME;
    desktopNoSlackCredentials = serve.serviceConfig.EnvironmentFile == [ ];
    desktopNotAppOwned = !(serve.environment ? HERMES_DESKTOP) && !(serve.environment ? HERMES_PARENT_PID);
    desktopNoClientDependency = !(lib.elem "graphical-session.target" serve.after);
    desktopOwnerAccess = unrestrictedUser serve;
    desktopPortPrivate = !(lib.elem enabled.services.hermes.desktop.port enabled.networking.firewall.allowedTCPPorts);
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
    ownerIdentity = unit.serviceConfig.User == "jordangarrison" && unit.serviceConfig.Group == "users";
    ownerHomeAccessible = unrestrictedUser unit;
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
