{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.herdr;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.herdr = {
    enable = mkEnableOption "herdr terminal workspace manager for AI coding agents";

    package = mkOption {
      type = types.package;
      default = pkgs.llm-agents.herdr;
      defaultText = literalExpression "pkgs.llm-agents.herdr";
      description = "The herdr package to install.";
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      example = literalExpression ''
        {
          onboarding = false;
          theme.name = "rose-pine";
          experimental.pane_history = true;
          session.resume_agents_on_restore = true;
        }
      '';
      description = ''
        Settings written to {file}`$XDG_CONFIG_HOME/herdr/config.toml`.

        Because Nix manages this file it becomes a read-only symlink: change
        settings here and rebuild rather than editing them in the herdr UI.
        herdr's mutable runtime state (session.json, session-history.json,
        logs, sockets, release-notes.json) is intentionally not managed and
        stays writable.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
      pkgs.herdr-handoff
    ];

    xdg.configFile."herdr/config.toml" = mkIf (cfg.settings != { }) {
      source = tomlFormat.generate "herdr-config.toml" cfg.settings;
    };
  };
}
