{ pkgs, config }:
let
  hermes = pkgs.llm-agents.hermes-agent;
  # buildPythonApplication is excluded from withPackages; expose its modules
  # explicitly while taking dependencies from the published package unchanged.
  python = pkgs.python3.withPackages (_: hermes.dependencies);
  env = config.systemd.services.hermes-gateway.environment;
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
  inherit (env) HERMES_MANAGED SLACK_ALLOWED_USERS SLACK_ALLOW_ALL_USERS GATEWAY_ALLOW_ALL_USERS;
} ''
  export HOME="$TMPDIR/home"
  export HERMES_HOME="$HOME/hermes"
  export HERMES_MANAGED_DIR="$TMPDIR/empty-managed"
  mkdir -p "$HERMES_MANAGED_DIR"
  mkdir -p "$HERMES_HOME"/{cron,sessions,logs,memories,skills}
  ln -s "$HERMES_TEST_CONFIG" "$HERMES_HOME/config.yaml"
  ln -s "$HERMES_TEST_PLUGINS" "$HERMES_HOME/plugins"
  python ${./hermes-runtime.py} > "$out"
  python ${./hermes-serve-smoke.py} >> "$out"
''
