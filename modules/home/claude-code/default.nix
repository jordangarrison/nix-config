# Claude Code (~/.claude) declarative management.
#
# Two mechanisms, chosen per file by who owns writes:
#
#  - Hand-authored files (global CLAUDE.md, workflows) are out-of-store
#    symlinks into the live nix-config checkout — edits are live without a
#    rebuild, same trade-off as programs.agent-skills.
#  - settings.json is MERGED on activation, not symlinked: Claude Code,
#    herdr (hook wiring), and plugin installs all mutate it at runtime, so
#    it must stay a regular writable file. Only the keys declared in
#    `settings` are asserted (declared wins, deep-merge); everything else —
#    permissions, hooks, enabledPlugins, env (holds an API key; repo is
#    public) — is never declared and never touched.
#
# Deliberately unmanaged: settings.local.json, hooks/ (herdr-owned),
# agents/ (pup-installed), plugins/, credentials, and all session state.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claude-code;
  jsonFormat = pkgs.formats.json { };
  declaredSettings = jsonFormat.generate "claude-code-declared-settings.json" cfg.settings;
  mkLive = path: config.lib.file.mkOutOfStoreSymlink path;
in
{
  # Upstream home-manager ships a programs.claude-code that writes
  # settings.json as a read-only store symlink — incompatible with Claude
  # Code/herdr runtime writes (permissions, hooks, plugins). This module
  # replaces it. If a home-manager bump moves/renames the upstream file,
  # eval fails loudly with an option collision — update this path then.
  disabledModules = [ "programs/claude-code.nix" ];

  options.programs.claude-code = {
    enable = lib.mkEnableOption "Claude Code declarative configuration";

    instructionsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path (in the live checkout) to the global instructions file.
        Symlinked out-of-store to ~/.claude/CLAUDE.md so edits are live
        without a rebuild.
      '';
    };

    files = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra hand-authored files under ~/.claude/, keyed by path relative
        to ~/.claude (e.g. "workflows/foo.js", "statusline.sh"), valued by
        absolute live-checkout path (out-of-store symlink). Reference them
        from settings via $HOME/.claude/<name>, never by checkout path.
      '';
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Settings deep-merged into ~/.claude/settings.json on activation.
        Declared keys win; undeclared keys (permissions, hooks, plugins,
        env) are left to Claude Code and herdr. The file stays writable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.settings ? env);
        message = "programs.claude-code.settings must not declare `env` — it carries API keys and this repo is public; leave it to the mutable settings.json.";
      }
    ];

    home.file =
      lib.optionalAttrs (cfg.instructionsFile != null) {
        ".claude/CLAUDE.md" = {
          source = mkLive cfg.instructionsFile;
          force = true; # adopt the pre-nix regular file
        };
      }
      // lib.mapAttrs' (
        name: path:
        lib.nameValuePair ".claude/${name}" {
          source = mkLive path;
          force = true;
        }
      ) cfg.files;

    # Out-of-store symlinks have zero build-time validation: a live path that
    # doesn't exist yet (branch not merged into the canonical checkout)
    # would silently replace the real files with dangling links. Fail early,
    # before checkLinkTargets/writeBoundary touch anything.
    home.activation.claudeCodeLivePathCheck =
      let
        livePaths = lib.optional (cfg.instructionsFile != null) cfg.instructionsFile ++ lib.attrValues cfg.files;
      in
      lib.mkIf (livePaths != [ ]) (
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          for p in ${lib.escapeShellArgs livePaths}; do
            if [[ ! -e "$p" ]]; then
              if [[ -n "''${AGENTS_LIVE_ALLOW_DANGLING:-}" ]]; then
                warnEcho "programs.claude-code: live path missing (allowed by AGENTS_LIVE_ALLOW_DANGLING): $p"
              else
                errorEcho "programs.claude-code: live path does not exist: $p"
                errorEcho "Merge/pull this content into the canonical checkout first, or set AGENTS_LIVE_ALLOW_DANGLING=1 to proceed anyway."
                exit 1
              fi
            fi
          done
        ''
      );

    # Runs between writeBoundary and herdr's integration install so ordering
    # is deterministic and herdr keeps the last word on hook wiring (we never
    # declare hooks, so either order is semantically safe).
    home.activation.claudeCodeSettingsMerge = lib.mkIf (cfg.settings != { }) (
      lib.hm.dag.entryBetween [ "herdrIntegrations" ] [ "writeBoundary" ] ''
        claudeSettings="$HOME/.claude/settings.json"
        if [[ -v DRY_RUN ]]; then
          echo "Would merge declared Claude Code settings into $claudeSettings"
        else
          mkdir -p "$HOME/.claude"
          if [[ -s "$claudeSettings" ]] && ${pkgs.jq}/bin/jq empty "$claudeSettings" 2>/dev/null; then
            (
              umask 077
              ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$claudeSettings" ${declaredSettings} \
                > "$claudeSettings.hm-merge"
            ) && mv "$claudeSettings.hm-merge" "$claudeSettings"
            chmod 600 "$claudeSettings" # env holds an API key; match the codex module
          elif [[ -s "$claudeSettings" ]]; then
            # Corrupt file: never overwrite runtime state, never abort the
            # whole activation over it — leave it for manual repair.
            warnEcho "$claudeSettings is not valid JSON; skipping declared-settings merge"
          else
            install -m 600 ${declaredSettings} "$claudeSettings"
          fi
        fi
      ''
    );
  };
}
