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

    integrations = mkOption {
      type = types.listOf (types.enum [
        "pi"
        "omp"
        "claude"
        "codex"
        "opencode"
        "hermes"
        "qodercli"
      ]);
      default = [ ];
      example = [
        "claude"
        "codex"
      ];
      description = ''
        herdr agent integrations to install and keep current on every
        activation, via `herdr integration install <name>`.

        herdr installs these hooks into per-agent dotfiles (e.g.
        {file}`~/.claude/hooks/herdr-agent-state.sh`) and bumps their version
        with each herdr release. The hooks record the agent's native session
        id, which is what `session.resume_agents_on_restore` needs to resume a
        conversation after a server restart. Re-running the installer on every
        rebuild keeps the hooks in sync with the installed herdr version, so
        agent-session resume keeps working across herdr updates instead of
        silently breaking when the integration version drifts.

        These hooks live in mutable dotfiles outside the Nix store (that is how
        herdr ships them); this option only keeps them current, it does not
        manage their contents declaratively.
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

    # Keep the agent integration hooks in sync with the installed herdr
    # version on every activation. Install is idempotent and writes only to
    # per-agent dotfiles; a failure is non-fatal so it never aborts a switch.
    home.activation.herdrIntegrations = mkIf (cfg.integrations != [ ]) (
      hm.dag.entryAfter [ "writeBoundary" ] (
        concatMapStringsSep "\n" (agent: ''
          run ${cfg.package}/bin/herdr integration install ${agent} \
            || echo "herdr: 'integration install ${agent}' failed (non-fatal)" >&2
        '') cfg.integrations
      )
    );
  };
}
