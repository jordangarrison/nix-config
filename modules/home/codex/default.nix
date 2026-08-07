# Codex (~/.codex) declarative management.
#
# Same split as modules/home/claude-code:
#
#  - Hand-authored files (AGENTS.md, rules/*.rules) are out-of-store
#    symlinks into the live checkout — live edits, no rebuild.
#  - config.toml is MERGED on activation, never symlinked: codex writes
#    [projects."…"] trust_level and [hooks.state."…"] trusted_hash entries
#    at runtime, and herdr manages hook wiring. Only declared keys are
#    asserted (deep-merge, declared wins). [otel] is deliberately never
#    declared — its exporter headers embed a Datadog API key and this repo
#    is public. File mode is kept 0600.
#
# Deliberately unmanaged: hooks.json + herdr-agent-state.sh (herdr-owned),
# auth.json, history, sqlite state, caches, sessions.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.codex;
  tomlFormat = pkgs.formats.toml { };
  declaredConfig = tomlFormat.generate "codex-declared-config.toml" cfg.config;
  mkLive = path: config.lib.file.mkOutOfStoreSymlink path;

  mergePython = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);
  mergeScript = pkgs.writeText "codex-config-merge.py" ''
    import copy
    import os
    import sys
    import tomllib

    import tomli_w

    existing_path, declared_path = sys.argv[1], sys.argv[2]

    existing = {}
    if os.path.exists(existing_path):
        try:
            with open(existing_path, "rb") as f:
                existing = tomllib.load(f)
        except tomllib.TOMLDecodeError as e:
            # Corrupt file: never overwrite runtime state (trust entries,
            # hook state), never abort the whole activation over it.
            print(
                f"warning: {existing_path} is not valid TOML ({e}); "
                "skipping declared-config merge",
                file=sys.stderr,
            )
            sys.exit(0)
    with open(declared_path, "rb") as f:
        declared = tomllib.load(f)

    def merge(base, overlay):
        for key, value in overlay.items():
            if isinstance(value, dict) and isinstance(base.get(key), dict):
                merge(base[key], value)
            else:
                base[key] = value

    merged = copy.deepcopy(existing)
    merge(merged, declared)

    # No drift: don't rewrite. tomli_w re-serialization strips comments and
    # reorders keys, so only pay that cost when a declared key actually
    # needs correcting.
    if merged == existing and os.path.exists(existing_path):
        sys.exit(0)

    # 0600 from the first byte — the file carries a Datadog API key.
    tmp = existing_path + ".hm-merge"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        tomli_w.dump(merged, f)
    os.replace(tmp, existing_path)
    os.chmod(existing_path, 0o600)
  '';
in
{
  # Upstream home-manager ships a programs.codex that writes config.toml as
  # a read-only store symlink — incompatible with codex/herdr runtime writes
  # (trust entries, hook state). This module replaces it.
  disabledModules = [ "programs/codex.nix" ];

  options.programs.codex = {
    enable = lib.mkEnableOption "Codex declarative configuration";

    instructionsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path (in the live checkout) to the global instructions file.
        Symlinked out-of-store to ~/.codex/AGENTS.md.
      '';
    };

    rules = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Rule files for ~/.codex/rules/, keyed by filename, valued by
        absolute live-checkout path (out-of-store symlink).
      '';
    };

    config = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      description = ''
        Config deep-merged into ~/.codex/config.toml on activation.
        Declared keys win; undeclared keys ([projects], [hooks.state],
        [otel]) are left to codex and herdr. The file stays writable, 0600.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.config ? otel);
        message = "programs.codex.config must not declare `otel` — its exporter headers carry an API key and this repo is public; leave it to the mutable config.toml.";
      }
    ];

    home.file =
      lib.optionalAttrs (cfg.instructionsFile != null) {
        ".codex/AGENTS.md" = {
          source = mkLive cfg.instructionsFile;
          force = true; # adopt the pre-nix regular file
        };
      }
      // lib.mapAttrs' (
        name: path:
        lib.nameValuePair ".codex/rules/${name}" {
          source = mkLive path;
          force = true;
        }
      ) cfg.rules;

    # See the equivalent block in modules/home/claude-code for rationale.
    home.activation.codexLivePathCheck =
      let
        livePaths = lib.optional (cfg.instructionsFile != null) cfg.instructionsFile ++ lib.attrValues cfg.rules;
      in
      lib.mkIf (livePaths != [ ]) (
        lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
          for p in ${lib.escapeShellArgs livePaths}; do
            if [[ ! -e "$p" ]]; then
              if [[ -n "''${AGENTS_LIVE_ALLOW_DANGLING:-}" ]]; then
                warnEcho "programs.codex: live path missing (allowed by AGENTS_LIVE_ALLOW_DANGLING): $p"
              else
                errorEcho "programs.codex: live path does not exist: $p"
                errorEcho "Merge/pull this content into the canonical checkout first, or set AGENTS_LIVE_ALLOW_DANGLING=1 to proceed anyway."
                exit 1
              fi
            fi
          done
        ''
      );

    # Deterministic ordering vs herdr's hook install; see claude-code module.
    home.activation.codexConfigMerge = lib.mkIf (cfg.config != { }) (
      lib.hm.dag.entryBetween [ "herdrIntegrations" ] [ "writeBoundary" ] ''
        codexConfig="$HOME/.codex/config.toml"
        if [[ -v DRY_RUN ]]; then
          echo "Would merge declared codex config into $codexConfig"
        else
          mkdir -p "$HOME/.codex"
          ${mergePython}/bin/python3 ${mergeScript} "$codexConfig" ${declaredConfig}
        fi
      ''
    );
  };
}
