# Cursor Agent CLI (~/.cursor/cli-config.json) declarative management.
#
# Same split as modules/home/claude-code:
#
#  - cli-config.json is MERGED on activation, not symlinked: the CLI writes
#    authInfo, model selection, privacyCache, and the permissions allowlist
#    at runtime, so the file must stay a regular writable file. Only the
#    keys declared in `settings` are asserted (declared wins, deep-merge).
#  - Do not declare authInfo, model/selectedModel, privacyCache, or
#    permissions — those are CLI-owned. This repo is public.
#
# Deliberately unmanaged: project `.cursor/cli.json` overlays, IDE settings,
# and all other ~/.cursor/ runtime state.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.cursor-agent;
  jsonFormat = pkgs.formats.json { };
  declaredSettings = jsonFormat.generate "cursor-agent-declared-settings.json" cfg.settings;
in
{
  options.programs.cursor-agent = {
    enable = lib.mkEnableOption "Cursor Agent CLI declarative configuration";

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Settings deep-merged into ~/.cursor/cli-config.json on activation.
        Declared keys win; undeclared keys (authInfo, model, permissions,
        privacyCache) are left to the CLI. The file stays writable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.settings ? authInfo);
        message = "programs.cursor-agent.settings must not declare `authInfo` — it is CLI-owned credentials and this repo is public; leave it to the mutable cli-config.json.";
      }
    ];

    # Deterministic ordering vs herdr's integration install; see claude-code.
    home.activation.cursorAgentSettingsMerge = lib.mkIf (cfg.settings != { }) (
      lib.hm.dag.entryBetween [ "herdrIntegrations" ] [ "writeBoundary" ] ''
        cursorSettings="$HOME/.cursor/cli-config.json"
        if [[ -v DRY_RUN ]]; then
          echo "Would merge declared Cursor Agent settings into $cursorSettings"
        else
          mkdir -p "$HOME/.cursor"
          if [[ -s "$cursorSettings" ]] && ${pkgs.jq}/bin/jq empty "$cursorSettings" 2>/dev/null; then
            (
              umask 077
              ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$cursorSettings" ${declaredSettings} \
                > "$cursorSettings.hm-merge"
            ) && mv "$cursorSettings.hm-merge" "$cursorSettings"
            chmod 600 "$cursorSettings"
          elif [[ -s "$cursorSettings" ]]; then
            # Corrupt file: never overwrite runtime state, never abort the
            # whole activation over it — leave it for manual repair.
            warnEcho "$cursorSettings is not valid JSON; skipping declared-settings merge"
          else
            install -m 600 ${declaredSettings} "$cursorSettings"
          fi
        fi
      ''
    );
  };
}
