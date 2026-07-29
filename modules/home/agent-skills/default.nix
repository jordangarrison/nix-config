# Cross-agent skills fan-out.
#
# Skills live in one canonical directory in this repo and are symlinked
# (out-of-store, so edits are live without a rebuild) into:
#   ~/.agents/skills/<name>  — read natively by codex, pi, and opencode
#   ~/.claude/skills/<name>  — Claude Code only reads its own directory
#
# Adding a new skill: create <skillsDir>/<name>/SKILL.md in the checkout,
# `git add` it (flake eval only sees tracked files), and rebuild once to
# plant the symlinks. Content edits after that need no rebuild.
#
# Names must stay disjoint from skills.sh-managed installs, which own
# their own entries in the same directories.
{ config, lib, ... }:
let
  cfg = config.programs.agent-skills;
in
{
  options.programs.agent-skills = {
    enable = lib.mkEnableOption "cross-agent skills fan-out";

    skillsDir = lib.mkOption {
      type = lib.types.path;
      description = "In-repo skills directory, used to enumerate skill names at eval time.";
    };

    liveDir = lib.mkOption {
      type = lib.types.str;
      description = ''
        Absolute path to the same skills directory in the live checkout.
        Symlink targets point here (out-of-store) so skills are editable
        without a rebuild.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file =
      let
        names = lib.attrNames (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir cfg.skillsDir)
        );
        mkLinks = name: {
          ".agents/skills/${name}".source =
            config.lib.file.mkOutOfStoreSymlink "${cfg.liveDir}/${name}";
          ".claude/skills/${name}".source =
            config.lib.file.mkOutOfStoreSymlink "${cfg.liveDir}/${name}";
        };
      in
      lib.mkMerge (map mkLinks names);
  };
}
