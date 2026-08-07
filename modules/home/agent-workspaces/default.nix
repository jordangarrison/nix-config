# Workspace router fan-out.
#
# One generic ROUTER.md (tracked in this repo) serves every workspace folder
# under ~/dev as its AGENTS.md, via out-of-store symlinks — edits are live
# without a rebuild. Workspace-specific content lives NEXT TO the symlink,
# where the router tells agents to look:
#
#   <ws>/AGENTS.md      -> ROUTER.md (this module, out-of-store symlink)
#   <ws>/CLAUDE.md      -> AGENTS.md (this module)
#   <ws>/.workspace.json   generated repo inventory (workspace-inventory
#                          skill; never managed here)
#   <ws>/ADDITIONS.md      workspace-specific conventions. Either symlinked
#                          from this repo (additionsFile) or a plain local
#                          untracked file (additionsFile = null) — used for
#                          work workspaces whose content must stay out of
#                          this public repo. The router reads whichever is
#                          present.
{ config, lib, ... }:

let
  cfg = config.programs.agent-workspaces;
  mkLive = path: config.lib.file.mkOutOfStoreSymlink path;

  workspaceType = lib.types.submodule {
    options = {
      directory = lib.mkOption {
        type = lib.types.str;
        description = "Workspace folder, relative to the home directory (e.g. \"dev/flocasts\").";
      };

      additionsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Absolute live-checkout path symlinked to <workspace>/ADDITIONS.md.
          Leave null for workspaces whose additions are a local untracked
          file instead.
        '';
      };
    };
  };

  mkWorkspace =
    _name: ws:
    {
      "${ws.directory}/AGENTS.md" = {
        source = mkLive cfg.routerFile;
        force = true; # adopt the pre-nix regular file
      };
      # Points at the router directly (not at the sibling AGENTS.md) to keep
      # the resolution chain short — some tools are picky about multi-hop
      # symlinks.
      "${ws.directory}/CLAUDE.md" = {
        source = mkLive cfg.routerFile;
        force = true;
      };
    }
    // lib.optionalAttrs (ws.additionsFile != null) {
      "${ws.directory}/ADDITIONS.md" = {
        source = mkLive ws.additionsFile;
        force = true;
      };
    };
in
{
  options.programs.agent-workspaces = {
    enable = lib.mkEnableOption "generic workspace router fan-out";

    routerFile = lib.mkOption {
      type = lib.types.str;
      description = "Absolute live-checkout path of the generic ROUTER.md.";
    };

    workspaces = lib.mkOption {
      type = lib.types.attrsOf workspaceType;
      default = { };
      description = "Workspace folders to plant the router into.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (lib.mapAttrsToList mkWorkspace cfg.workspaces);

    # See the equivalent block in modules/home/claude-code for rationale.
    home.activation.agentWorkspacesLivePathCheck =
      let
        livePaths = [
          cfg.routerFile
        ]
        ++ lib.filter (p: p != null) (lib.mapAttrsToList (_: ws: ws.additionsFile) cfg.workspaces);
      in
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        for p in ${lib.escapeShellArgs livePaths}; do
          if [[ ! -e "$p" ]]; then
            if [[ -n "''${AGENTS_LIVE_ALLOW_DANGLING:-}" ]]; then
              warnEcho "programs.agent-workspaces: live path missing (allowed by AGENTS_LIVE_ALLOW_DANGLING): $p"
            else
              errorEcho "programs.agent-workspaces: live path does not exist: $p"
              errorEcho "Merge/pull this content into the canonical checkout first, or set AGENTS_LIVE_ALLOW_DANGLING=1 to proceed anyway."
              exit 1
            fi
          fi
        done
      '';
  };
}
