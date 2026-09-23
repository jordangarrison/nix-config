# Cross-agent skills fan-out.
#
# Every skill is linked into both:
#   ~/.agents/skills/<name>  — read natively by codex, pi, omp, and opencode
#   ~/.claude/skills/<name>  — Claude Code only reads its own directory
#
# Two kinds of skill, kept apart because they change differently:
#
#  - Repo-owned skills live in `skillsDir` and are linked out-of-store into
#    the live checkout, so edits are live without a rebuild. Adding one:
#    create <skillsDir>/<name>/SKILL.md, `git add` it (flake eval only sees
#    tracked files), and rebuild once to plant the symlinks.
#  - Upstream skills are declared in `external` as store paths: a flake input
#    subdirectory, or a path from the Nix package of the CLI the skill
#    documents, so skill and CLI versions move together. They update with the
#    flake inputs or packages they come from.
#
# Never install skills imperatively (`npx skills`, `pup skills install`,
# `readwise skills install`, `flo skills add`, hand copies). If one takes a
# declared name, the next switch on a NixOS/darwin host moves it aside to
# `<name>.backup` (home-manager.backupFileExtension), and agents then load
# that stale copy as a duplicate skill. A conflicting symlink, or any
# conflict under standalone Home Manager without `-b`, fails the switch.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agent-skills;

  repoNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir cfg.skillsDir)
  );

  collisions = lib.filter (name: lib.elem name repoNames) (lib.attrNames cfg.external);

  # Checks every external skill at build time, not eval time: builtins.pathExists
  # on a package source would force it to be fetched during evaluation.
  # Copies (not links) each skill so the closure holds only the skill
  # directories, not the whole source trees and packages they come from.
  externalBundle = pkgs.runCommand "agent-skills-external" { } ''
    mkdir $out
    ${lib.concatStrings (
      lib.mapAttrsToList (name: src: ''
        if [ ! -f ${lib.escapeShellArg "${src}"}/SKILL.md ]; then
          echo "agent-skills: ${name}: no SKILL.md in ${src}" >&2
          exit 1
        fi
        cp -rL --no-preserve=mode ${lib.escapeShellArg "${src}"} $out/${lib.escapeShellArg name}
      '') cfg.external
    )}
  '';

  mkLinks = name: source: {
    ".agents/skills/${name}".source = source;
    ".claude/skills/${name}".source = source;
  };
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

    external = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      example = lib.literalExpression ''
        { gh-stack = "''${pkgs.gh-stack.src}/skills/gh-stack"; }
      '';
      description = ''
        Upstream skills: skill name to a store directory containing SKILL.md.
        Names must not collide with repo-owned skills in `skillsDir`.
      '';
    };

    bundle = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        The built bundle of external skills. Exposed so CI can build it:
        evaluation alone never runs the SKILL.md check.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.agent-skills.bundle = externalBundle;

    assertions = [
      {
        assertion = collisions == [ ];
        message = "programs.agent-skills: external skills collide with repo-owned skills: ${lib.concatStringsSep ", " collisions}";
      }
    ];

    home.file = lib.mkMerge (
      map (name: mkLinks name (config.lib.file.mkOutOfStoreSymlink "${cfg.liveDir}/${name}")) repoNames
      ++ lib.mapAttrsToList (name: _: mkLinks name "${externalBundle}/${name}") cfg.external
    );
  };
}
