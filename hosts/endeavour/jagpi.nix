# Home Manager module: the always-on jagpi daemon on endeavour.
#
# The jagpi module runs `jagpi daemon --instance default` as the user unit
# jagpi-default.service, writes ~/.config/jagpi/default/config.json, and puts
# `jagpi` on PATH (the TUI, and `jagpi notify` for workers). The instance's
# state stays in ~/.local/state/jagpi/default. Options: jagpi's
# nix/home-manager.nix.
#
# Lifetime: endeavour declares linger for jordangarrison, so default.target
# starts at boot and stays up after logout. Start the self-managed hc core
# before jagpi; hc itself owns its transient core and terminal-holder units.
{
  config,
  inputs,
  pkgs,
  ...
}:

{
  imports = [ inputs.jagpi.homeManagerModules.default ];

  systemd.user.services.hc-core = {
    Unit = {
      Description = "Start the self-managed Herdr core";
      # Fresh machines can install hc later through the desktop app (ADR 007).
      ConditionPathExists = "%h/.local/bin/hc";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "%h/.local/bin/hc server start";
      RemainAfterExit = true;
      # No ExecStop: stopping this bootstrap must not stop the shared core or
      # its holders. hc starts those in separate transient user units, and
      # server start is a no-op when the core is already running.
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.jagpi-default.Unit = {
    Wants = [ "hc-core.service" ];
    After = [ "hc-core.service" ];
  };

  services.jagpi = {
    enable = true;
    instance = "default";

    # T3 launches the upstream wrapper against this same user daemon.
    # Requires a jagpi input with services.jagpi.acp.enable; see the T3 runbook.
    acp.enable = true;

    # The herdr the TUI uses, so the daemon's workers talk to the same server.
    herdr.package = config.programs.herdr.package;

    # No extraPackages: git, gh, jq, herdr, nix, and nh are already on the
    # unit's PATH through the user profile and the system profile.

    # Claude (subscription) models through jagpi's own claude-bridge
    # package (jagpi ADR 0025, docs/providers.md); its passthru.jagpiProvider
    # names the entry module. It runs the same Nix-managed claude that
    # home.nix gives pi's bridge, so no claude goes on the unit's PATH. No
    # model or tiers here: which bot uses Claude is set apart from this.
    providers = [
      {
        package = inputs.jagpi.packages.${pkgs.stdenv.hostPlatform.system}.claude-bridge;
        options.pathToClaudeCodeExecutable = "${pkgs.llm-agents.claude-code}/bin/claude";
      }
    ];

    # Slack: the jagpi app (A0CEC4LHTNV) in the FloSports workspace, created
    # from jagpi's packages/slack/manifest.json with the Slack CLI (jagpi
    # docs/slack-app.md, ADR 0026). Not JordanBot: Hermes keeps that app.
    # The file is mode 600 and outside the store, with SLACK_BOT_TOKEN and
    # SLACK_APP_TOKEN. systemd does not start the unit while it is missing.
    environmentFile = "/home/jordangarrison/.config/jagpi/slack.env";
    settings.owners.slack = [ "UQ69UGHKM" ];
    # Repos where members may ask a worker to review a PR (jagpi ADR 0029):
    # every repo of each FloSports enterprise org.
    settings.reviews.repos = [
      "flocasts/*"
      "milesplit/*"
      "HockeyTech/*"
      "DirectAthletics/*"
      "flo-eng-leaders/*"
      "KartingCoach/*"
    ];
  };
}
