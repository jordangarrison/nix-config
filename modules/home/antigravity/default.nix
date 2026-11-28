# Google Antigravity (~/.gemini/config + ~/.gemini/antigravity-cli) declarative
# management.
#
# Same split as modules/home/claude-code and modules/home/cursor-agent:
#
#  - Hand-authored global instructions are an out-of-store symlink at
#    ~/.gemini/config/AGENTS.md into the live checkout — live edits, no rebuild.
#    Using ~/.gemini/config/AGENTS.md avoids clobbering ~/.gemini/GEMINI.md
#    (which external tools like nodeterm may write to).
#  - ~/.gemini/antigravity-cli/settings.json is MERGED on activation, not
#    symlinked: agy writes trustedWorkspaces and model selection at runtime, so
#    the file must stay a regular writable file. Only declared keys in
#    `settings` are asserted (declared wins, deep-merge).
#
# Deliberately unmanaged: credentials, sessions, history, logs, caches,
# ~/.gemini/config/mcp_config.json (managed by home.activation.mcpClientSync),
# and ~/.gemini/config/hooks/ (herdr-owned).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.antigravity-cli;
  jsonFormat = pkgs.formats.json { };
  declaredSettings = jsonFormat.generate "antigravity-cli-declared-settings.json" cfg.settings;
  mkLive = path: config.lib.file.mkOutOfStoreSymlink path;
in
{
  # Upstream home-manager ships a programs.antigravity-cli that installs
  # pkgs.antigravity-cli (we take agy from llm-agents) and manages context/MCP
  # differently from our live-checkout symlink + central mcpClientSync pattern.
  disabledModules = [ "programs/antigravity-cli.nix" ];

  options.programs.antigravity-cli = {
    enable = lib.mkEnableOption "Google Antigravity CLI declarative configuration";

    instructionsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path (in the live checkout) to the global instructions file.
        Symlinked out-of-store to ~/.gemini/config/AGENTS.md so edits are live
        without a rebuild.
      '';
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Settings deep-merged into ~/.gemini/antigravity-cli/settings.json on
        activation. Declared keys win; undeclared keys (trustedWorkspaces,
        model) are left to agy. The file stays writable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.optionalAttrs (cfg.instructionsFile != null) {
      ".gemini/config/AGENTS.md" = {
        source = mkLive cfg.instructionsFile;
        force = true; # adopt any pre-nix regular file
      };
    };

    # See the equivalent block in modules/home/claude-code for rationale.
    home.activation.antigravityLivePathCheck = lib.mkIf (cfg.instructionsFile != null) (
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [[ ! -e ${lib.escapeShellArg cfg.instructionsFile} ]]; then
          if [[ -n "''${AGENTS_LIVE_ALLOW_DANGLING:-}" ]]; then
            warnEcho "programs.antigravity: live path missing (allowed by AGENTS_LIVE_ALLOW_DANGLING): ${cfg.instructionsFile}"
          else
            errorEcho "programs.antigravity: live path does not exist: ${cfg.instructionsFile}"
            errorEcho "Merge/pull this content into the canonical checkout first, or set AGENTS_LIVE_ALLOW_DANGLING=1 to proceed anyway."
            exit 1
          fi
        fi
      ''
    );

    # Deterministic ordering vs herdr's hook install; see claude-code module.
    home.activation.antigravitySettingsMerge = lib.mkIf (cfg.settings != { }) (
      lib.hm.dag.entryBetween [ "herdrIntegrations" ] [ "writeBoundary" ] ''
        agySettings="$HOME/.gemini/antigravity-cli/settings.json"
        if [[ -v DRY_RUN ]]; then
          echo "Would merge declared Antigravity CLI settings into $agySettings"
        else
          mkdir -p "$HOME/.gemini/antigravity-cli"
          if [[ -s "$agySettings" ]] && ${pkgs.jq}/bin/jq empty "$agySettings" 2>/dev/null; then
            (
              umask 077
              ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$agySettings" ${declaredSettings} \
                > "$agySettings.hm-merge"
            ) && mv "$agySettings.hm-merge" "$agySettings"
            chmod 600 "$agySettings"
          elif [[ -s "$agySettings" ]]; then
            # Corrupt file: never overwrite runtime state, never abort the
            # whole activation over it — leave it for manual repair.
            warnEcho "$agySettings is not valid JSON; skipping declared-settings merge"
          else
            install -m 600 ${declaredSettings} "$agySettings"
          fi
        fi
      ''
    );
  };
}
