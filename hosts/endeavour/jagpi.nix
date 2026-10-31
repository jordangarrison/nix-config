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

    # T3 launches the upstream wrapper against this same user daemon.
    # Requires a jagpi input with services.jagpi.acp.enable; see the T3 runbook.
    acp.enable = true;

    # The herdr the TUI uses, so the daemon's workers talk to the same server.
    herdr.package = config.programs.herdr.package;

    # No extraPackages: git, gh, jq, herdr, nix, and nh are already on the
    # unit's PATH through the user profile and the system profile.

    # Claude (subscription) models through the claude-bridge's jagpi entry
    # (jagpi docs/providers.md). It runs the same Nix-managed claude that
    # home.nix gives pi's bridge, so no claude goes on the unit's PATH. No
    # model or tiers here: which bot uses Claude is set apart from this.
    providers = [
      {
        package = inputs.pi-extensions.packages.${pkgs.stdenv.hostPlatform.system}.claude-bridge;
        options.pathToClaudeCodeExecutable = "${pkgs.llm-agents.claude-code}/bin/claude";
      }
    ];

    # Slack: no app or tokens yet. Follow jagpi's docs/slack-app.md, then set
    # the file with SLACK_BOT_TOKEN and SLACK_APP_TOKEN (and owners.slack in
    # settings):
    # environmentFile = "/home/jordangarrison/.config/jagpi/slack.env";
  };
}
