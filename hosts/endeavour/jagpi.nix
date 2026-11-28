# Home Manager module: the always-on jagpi daemon on endeavour.
#
# The jagpi module runs `jagpi daemon --instance default` as the user unit
# jagpi-default.service, writes ~/.config/jagpi/default/config.json, and puts
# `jagpi` on PATH (the TUI, and `jagpi notify` for workers). The instance's
# state stays in ~/.local/state/jagpi/default. Options: jagpi's
# nix/home-manager.nix.
#
# Lifetime: a user unit under default.target, so it starts at login, not at
# boot (Linger=no), and stops with the last session. That matches herdr, whose
# server the bot needs; boot-time availability would need linger plus a herdr
# service of its own.
{
  config,
  inputs,
  pkgs,
  ...
}:

{
  imports = [ inputs.jagpi.homeManagerModules.default ];

  services.jagpi = {
    enable = true;
    instance = "default";
    memory.caps.projects.agentic-blue-team = 4000;

    # T3 launches the upstream wrapper against this same user daemon.
    # Requires a jagpi input with services.jagpi.acp.enable; see the T3 runbook.
    acp.enable = true;

    # The herdr the TUI uses, so the daemon's workers talk to the same server.
    herdr.package = config.programs.herdr.package;

    # No extraPackages: git, gh, jq, herdr, nix, and nh are already on the
    # unit's PATH through the user profile and the system profile.

    # Subscription models through jagpi's own provider plugins (jagpi ADR 0025,
    # ADR 0084, docs/providers.md); each package's passthru.jagpiProvider names
    # its entry module. No model or tiers here: which bot uses which provider
    # is set apart from this.
    providers = [
      {
        package = inputs.jagpi.packages.${pkgs.stdenv.hostPlatform.system}.claude-bridge;
        options.pathToClaudeCodeExecutable = "${pkgs.llm-agents.claude-code}/bin/claude";
      }
      {
        package = inputs.jagpi.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-bridge;
        options.pathToAgyExecutable = "${pkgs.llm-agents.antigravity-cli}/bin/agy";
      }
    ];

    # Slack: the jagpi app (A0CEC4LHTNV) in the FloSports workspace, created
    # from jagpi's packages/slack/manifest.json with the Slack CLI (jagpi
    # docs/slack-app.md, ADR 0026). Not JordanBot: Hermes keeps that app.
    # The file is mode 600 and outside the store, with SLACK_BOT_TOKEN and
    # SLACK_APP_TOKEN. systemd does not start the unit while it is missing.
    environmentFile = "/home/jordangarrison/.config/flo-secrets/jagpi-slack.env";
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
