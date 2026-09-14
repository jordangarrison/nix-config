# OMP (~/.omp/agent) declarative management.
#
# Same split as modules/home/claude-code and modules/home/codex:
#
#  - Hand-authored files (the global AGENTS.md) are out-of-store symlinks
#    into the live checkout — live edits, no rebuild.
#  - config.yml is MERGED on activation, never symlinked: omp writes it at
#    runtime (`/settings`, `omp config set`, `setupVersion`, model-role
#    picks), so it must stay a regular writable file. Only declared keys are
#    asserted (deep-merge, declared wins). File mode is kept 0600 — the
#    schema holds `auth.broker.token`, and this repo is public.
#  - mcp.json is a read-only store symlink: the server list is fully
#    declarative here and holds no secrets (OAuth tokens live in agent.db).
#    Same trade-off pi already makes with ~/.config/mcp/mcp.json, and the
#    cost is the same: `/mcp add` cannot write, so add servers in Nix.
#
# Deliberately unmanaged: agent.db (OAuth credentials), models.db,
# history.db, sessions/, terminal-sessions/, cache/, and extensions/
# (herdr owns herdr-omp-agent-state.ts there).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.omp;
  yamlFormat = pkgs.formats.yaml { };
  declaredSettings = yamlFormat.generate "omp-declared-config.yml" cfg.settings;
  mkLive = path: config.lib.file.mkOutOfStoreSymlink path;

  mergePython = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
  mergeScript = pkgs.writeText "omp-config-merge.py" ''
    import copy
    import os
    import sys

    import yaml

    existing_path, declared_path = sys.argv[1], sys.argv[2]


    def load(path):
        with open(path, "rb") as f:
            return yaml.safe_load(f)


    existing = {}
    if os.path.exists(existing_path):
        try:
            loaded = load(existing_path)
        except yaml.YAMLError as e:
            # Corrupt file: never overwrite runtime state (model roles,
            # setupVersion), never abort the whole activation over it.
            print(
                f"warning: {existing_path} is not valid YAML ({e}); "
                "skipping declared-config merge",
                file=sys.stderr,
            )
            sys.exit(0)
        if loaded is None:
            loaded = {}
        if not isinstance(loaded, dict):
            print(
                f"warning: {existing_path} is not a YAML mapping; "
                "skipping declared-config merge",
                file=sys.stderr,
            )
            sys.exit(0)
        existing = loaded

    declared = load(declared_path) or {}


    def merge(base, overlay):
        for key, value in overlay.items():
            if isinstance(value, dict) and isinstance(base.get(key), dict):
                merge(base[key], value)
            else:
                base[key] = value


    merged = copy.deepcopy(existing)
    merge(merged, declared)

    # No drift: don't rewrite. safe_dump re-serialization strips comments and
    # normalizes style, so only pay that cost when a declared key actually
    # needs correcting.
    if merged == existing and os.path.exists(existing_path):
        sys.exit(0)

    # 0600 from the first byte — the schema can carry auth.broker.token.
    tmp = existing_path + ".hm-merge"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        yaml.safe_dump(merged, f, sort_keys=False, default_flow_style=False)
    os.replace(tmp, existing_path)
    os.chmod(existing_path, 0o600)
  '';
in
{
  options.programs.omp = {
    enable = lib.mkEnableOption "OMP coding agent declarative configuration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.llm-agents.omp;
      defaultText = lib.literalExpression "pkgs.llm-agents.omp";
      description = "The omp package to install.";
    };

    instructionsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path (in the live checkout) to the user-level context file.
        Symlinked out-of-store to {file}`~/.omp/agent/AGENTS.md` so edits are
        live without a rebuild.

        This is the native user-level context file, which outranks every
        other provider's. Without it omp has no user context at all: foreign
        user roots such as {file}`~/.claude/CLAUDE.md` are gated behind the
        `enabledProviders` setting, which defaults to empty.
      '';
    };

    settings = lib.mkOption {
      type = yamlFormat.type;
      default = { };
      description = ''
        Settings deep-merged into {file}`~/.omp/agent/config.yml` on
        activation. Declared keys win; undeclared keys are left to omp. The
        file stays writable.

        Two consequences of the merge, since omp also writes this file:

        - Objects merge key by key, but arrays are replaced wholesale.
        - The merge only adds and overwrites; it never prunes. Removing a key
          here leaves the last written value in the file, so drop it from the
          file by hand when a declarative setting is retired.

        Declaring `modelRoles` therefore resets a runtime `/model` pick at
        the next activation, the same way
        `programs.claude-code.settings.model` does.
      '';
    };

    mcpConfigSource = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression ''config.xdg.configFile."mcp/mcp.json".source'';
      description = ''
        Store path to an `mcp.json` linked read-only to
        {file}`~/.omp/agent/mcp.json`. omp does not read
        {file}`~/.config/mcp/mcp.json` (that path belongs to pi's MCP
        adapter), and its own importers for `~/.claude.json` /
        `~/.codex/config.toml` are gated behind `enabledProviders`, so
        without this omp starts with no user-level MCP servers.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.settings ? auth);
        message = "programs.omp.settings must not declare `auth` — it carries the auth-broker token and this repo is public; leave it to the mutable config.yml.";
      }
    ];

    home.packages = [ cfg.package ];

    home.file =
      lib.optionalAttrs (cfg.instructionsFile != null) {
        ".omp/agent/AGENTS.md" = {
          source = mkLive cfg.instructionsFile;
          force = true; # adopt a pre-nix regular file
        };
      }
      // lib.optionalAttrs (cfg.mcpConfigSource != null) {
        ".omp/agent/mcp.json".source = cfg.mcpConfigSource;
      };

    # Out-of-store symlinks have zero build-time validation: a live path that
    # doesn't exist yet (branch not merged into the canonical checkout) would
    # silently replace the real file with a dangling link. Fail early, before
    # checkLinkTargets/writeBoundary touch anything.
    home.activation.ompLivePathCheck = lib.mkIf (cfg.instructionsFile != null) (
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        if [[ ! -e ${lib.escapeShellArg cfg.instructionsFile} ]]; then
          if [[ -n "''${AGENTS_LIVE_ALLOW_DANGLING:-}" ]]; then
            warnEcho "programs.omp: live path missing (allowed by AGENTS_LIVE_ALLOW_DANGLING): ${cfg.instructionsFile}"
          else
            errorEcho "programs.omp: live path does not exist: ${cfg.instructionsFile}"
            errorEcho "Merge/pull this content into the canonical checkout first, or set AGENTS_LIVE_ALLOW_DANGLING=1 to proceed anyway."
            exit 1
          fi
        fi
      ''
    );

    # Runs between writeBoundary and herdr's integration install, matching the
    # claude-code module, so ordering is deterministic across agent modules.
    home.activation.ompConfigMerge = lib.mkIf (cfg.settings != { }) (
      lib.hm.dag.entryBetween [ "herdrIntegrations" ] [ "writeBoundary" ] ''
        ompConfig="$HOME/.omp/agent/config.yml"
        if [[ -v DRY_RUN ]]; then
          echo "Would merge declared OMP settings into $ompConfig"
        else
          mkdir -p "$HOME/.omp/agent"
          run ${mergePython}/bin/python3 ${mergeScript} "$ompConfig" ${declaredSettings}
        fi
      ''
    );
  };
}
