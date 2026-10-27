# Home Manager module: the always-on jagpi daemon on endeavour.
#
# The jagpi module runs `jagpi daemon --instance default` as the user unit
# jagpi-default.service, writes ~/.config/jagpi/default/config.json, and puts
# `jagpi` on PATH (the TUI, and `jagpi notify` for workers). The instance's
# state stays in ~/.local/state/jagpi/default. Options: jagpi's
# nix/home-manager.nix.
{ config, inputs, ... }:

{
  imports = [ inputs.jagpi.homeManagerModules.default ];

  services.jagpi = {
    enable = true;
    instance = "default";

    # The herdr the TUI uses, so the daemon's workers talk to the same server.
    herdr.package = config.programs.herdr.package;

    # No extraPackages: git, gh, jq, herdr, nix, and nh are already on the
    # unit's PATH through the user profile and the system profile.

    # Slack: no app or tokens yet. Follow jagpi's docs/slack-app.md, then set
    # the file with SLACK_BOT_TOKEN and SLACK_APP_TOKEN (and owners.slack in
    # settings):
    # environmentFile = "/home/jordangarrison/.config/jagpi/slack.env";
  };
}
