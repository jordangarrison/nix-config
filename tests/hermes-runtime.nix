{ pkgs, config }:
let
  hermes = pkgs.llm-agents.hermes-agent;
  # buildPythonApplication is excluded from withPackages; expose its modules
  # explicitly while taking dependencies from the published package unchanged.
  python = pkgs.python3.withPackages (_: hermes.dependencies);
  env = config.systemd.services.hermes-gateway.environment;
  profiles = config.systemd.services.hermes-profiles;
  launcher = pkgs.lib.findFirst (pkg: pkgs.lib.getName pkg == "hermes-service")
    (throw "Hermes service launcher missing") config.environment.systemPackages;
  # Exercise the module's actual launchers in isolated homes on ephemeral ports.
  serveFixture = publicHost: (import (pkgs.path + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    system = pkgs.stdenv.hostPlatform.system;
    modules = [ ../modules/nixos/hermes.nix {
      system.stateVersion = "25.05";
      users.users.fixture.isNormalUser = true;
      services.hermes = {
        enable = true;
        user = "fixture";
        allowedUsers = [ "U0123456789" ];
        desktop = { enable = true; port = 0; inherit publicHost; };
      };
    } ];
  }).config.systemd.services;
  localFixture = serveFixture null;
  remoteFixture = serveFixture "hermes.jordangarrison.dev";
in
pkgs.runCommand "hermes-runtime-tests" {
  nativeBuildInputs = [ python ];
  PYTHONPATH = "${hermes}/${pkgs.python3.sitePackages}";
  HERMES_TEST_BINARY = "${hermes}/bin/hermes";
  HERMES_TEST_SERVE_LOCAL = localFixture.hermes-serve.serviceConfig.ExecStart;
  HERMES_TEST_SERVE_REMOTE = remoteFixture.hermes-serve.serviceConfig.ExecStart;
  HERMES_TEST_CONFIG = config.environment.etc."hermes-service/config.yaml".source;
  HERMES_TEST_PLUGINS = config.environment.etc."hermes-service/plugins".source;
  HERMES_TEST_LAUNCHER = "${launcher}/bin/hermes-service";
  HERMES_TEST_SERVICE_HOME = env.HERMES_HOME;
  HERMES_TEST_INSTRUCTIONS = ../users/jordangarrison/agents/AGENTS.md;
  HERMES_TEST_PROFILES_EXEC = profiles.serviceConfig.ExecStart;
  HERMES_TEST_PROFILES_PYTHONPATH = profiles.environment.PYTHONPATH;
  HERMES_TEST_PROFILES_SPEC = config.environment.etc."hermes-service/profiles.json".source;
  inherit (env) SLACK_ALLOWED_USERS SLACK_ALLOW_ALL_USERS GATEWAY_ALLOW_ALL_USERS;
} ''
  export HOME="$TMPDIR/home"
  export HERMES_HOME="$HOME/hermes"
  export HERMES_MANAGED_DIR="$TMPDIR/empty-managed"
  mkdir -p "$HERMES_MANAGED_DIR"
  mkdir -p "$HERMES_HOME"/{cron,sessions,logs,memories,skills}
  # Seed the service home with the unit's real command and the host's spec.
  python -c 'import json, os, sys; spec = json.load(open(sys.argv[1])); spec["home"] = os.environ["HERMES_HOME"]; json.dump(spec, open(sys.argv[2], "w"))' \
    "$HERMES_TEST_PROFILES_SPEC" "$TMPDIR/runtime-spec.json"
  ${pkgs.lib.removeSuffix " ${config.environment.etc."hermes-service/profiles.json".source}" profiles.serviceConfig.ExecStart} \
    "$TMPDIR/runtime-spec.json" > "$TMPDIR/seed.log"
  test -f "$HERMES_HOME/config.yaml" && ! test -L "$HERMES_HOME/config.yaml"
  ln -s "$HERMES_TEST_PLUGINS" "$HERMES_HOME/plugins"
  python ${./hermes-runtime.py} > "$out"
  python ${./hermes-serve-smoke.py} >> "$out"
  python ${./hermes-profiles.py} >> "$out"
  # The Slack gateway's gates and routing against the seeded service home.
  SLACK_BOT_TOKEN=xoxb-offline-fixture SLACK_APP_TOKEN=xapp-offline-fixture \
    python ${./hermes-slack-gateway.py} >> "$out"
''
