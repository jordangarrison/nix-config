{
  config,
  lib,
  pkgs,
  inputs,
  userApps ? { },
  ...
}:

let
  installHerdrT3 = pkgs.writeShellApplication {
    name = "install-herdr-t3";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      jq
      rsync
    ];
    text = builtins.readFile ./install-herdr-t3.sh;
  };

  installHerdrMods = pkgs.writeShellApplication {
    name = "install-herdr-mods";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      rsync
    ];
    text = builtins.readFile ./install-herdr-mods.sh;
  };

  # jagpi board (inputs.jagpi; `nix flake update jagpi` to update): jagpi's
  # own Herdr mod and layout (jagpi integrations/herdr-app), on every host.
  # A host that runs the jagpi daemon (services.jagpi, hosts/endeavour/
  # jagpi.nix) reads it here. Any other host runs jagpi on the daemon's
  # herdr-core machine (jagpi ADR 0070), so it needs no jagpi package.
  jagpiDaemonMachine = "endeavour"; # as `hc machine ls` names it
  jagpiBoardMachine = if config.services.jagpi.enable or false then null else jagpiDaemonMachine;
  jagpiBoardSrc = "${inputs.jagpi}/integrations/herdr-app";

  # Every jagpi-board content, wherever the layout puts it (blocks, a
  # stack's header), gets `machine`, so no copy that starts before the
  # board runs jagpi here.
  withMachine =
    value:
    if builtins.isList value then
      map withMachine value
    else if builtins.isAttrs value then
      let
        walked = lib.mapAttrs (_: withMachine) value;
      in
      if (value.mod or null) == "jagpi-board" then
        lib.recursiveUpdate walked { props.machine = jagpiBoardMachine; }
      else
        walked
    else
      value;

  jagpiLayout =
    if jagpiBoardMachine == null then
      "${jagpiBoardSrc}/layouts/jagpi.json"
    else
      builtins.toFile "jagpi.json" (
        builtins.toJSON (withMachine (lib.importJSON "${jagpiBoardSrc}/layouts/jagpi.json"))
      );

  # Third-party mods with more than one file: copied, not linked (see
  # install-herdr-mods.sh). Name in mods/ -> its folder in a flake input.
  copiedMods = {
    # Issues panel (inputs.herdr-issues; `nix flake update herdr-issues` to
    # update). GitHub issues of the focused terminal's repo, beside Files and
    # Changes. Runs gh, curl and `hc read`; caches issues, avatars and images
    # in ~/.config/herdr-app/data/issues/, which we do not manage.
    issues = "${inputs.herdr-issues}/mods/issues";
    # Vitals window (inputs.herdr-vitals; `nix flake update herdr-vitals`
    # to update). CPU, memory, and disks for this machine or a connected
    # one. First read downloads herdr-vitals onto that machine and runs it.
    # Not the TUI plugin.
    vitals = "${inputs.herdr-vitals}/app/mods/vitals";
    # Linear popup (inputs.herdr-linear; `nix flake update herdr-linear` to
    # update). Copied, not linked: it imports ./look.js and its own SVGs.
    # The Go binary from that same input is pre-placed below, where the mod's
    # [ -x ] check looks, so the mod does not download a release.
    linear = "${inputs.herdr-linear}/app/mods/linear";
    # jagpi board (see jagpiBoardSrc). Copied: it imports ./model.js and
    # its siblings.
    jagpi-board = "${jagpiBoardSrc}/mods/jagpi-board";
    # Revive (inputs.herdr-revive, pinned to a release tag). Resumes the
    # agent a herdr-core terminal lost to a reboot. Its record lives in
    # `revive.*` terminal labels; it writes no files at runtime. Its pi
    # extension, zsh block and Claude Code hooks are wired below.
    revive = "${inputs.herdr-revive}/mods/revive";
  };

  # Revive runs from the copy in mods/, not the store: its Claude Code hooks
  # name this path, so it stays the same across updates.
  reviveDir = "${config.xdg.configHome}/herdr-app/mods/revive";

  # Revive's own zsh block, generated from the pinned source rather than
  # copied, so an update cannot leave a stale copy. `revive.mjs install`
  # would append it to ~/.zshrc, which is a read-only Nix symlink here.
  # The engine path comes first: revive.mjs runs its CLI when argv[1] is itself.
  reviveZshBlock = pkgs.runCommand "herdr-revive-zsh-block" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node --input-type=module -e '
      const { shellBlock } = await import(process.argv[2]);
      process.stdout.write(shellBlock(process.argv[1]) + "\n");
    ' ${lib.escapeShellArg "${reviveDir}/revive.mjs"} ${inputs.herdr-revive}/mods/revive/revive.mjs > $out
    grep -q '# >>> herdr-revive >>>' $out
  '';

  # The mod pins this string and looks up ~/.local/share/herdr-linear/app/<it>/.
  linearVersion =
    let
      line = lib.findFirst (l: lib.hasPrefix "export const LINEAR_VERSION = " l) "" (
        lib.splitString "\n" (builtins.readFile "${inputs.herdr-linear}/app/mods/linear/main.js")
      );
      matched = builtins.match "export const LINEAR_VERSION = \"([^\"]+)\";" line;
    in
    if matched == null then
      throw "herdr-linear: LINEAR_VERSION not found in app/mods/linear/main.js"
    else
      builtins.head matched;

  herdrLinear = pkgs.callPackage ../../../packages/herdr-linear {
    src = inputs.herdr-linear;
    version = linearVersion;
  };
in
{
  config = lib.mkIf (userApps.herdr-app.enable or false) {
    home.packages = [
      (import ./package.nix { inherit pkgs; })
      herdrLinear
    ];

    # The mod never searches PATH. An executable at this exact path makes its
    # provision script print the path and exit, before curl. The script uses
    # $HOME/.local/share, not XDG_DATA_HOME.
    home.file.".local/share/herdr-linear/app/${linearVersion}/herdr-linear".source =
      lib.getExe herdrLinear;

    # Keep personal configuration declarative, as with herdr/config.toml.
    # The work-items layout and mod are ours. Do not manage layouts/.state,
    # shared.json, or the app-generated guide, types, shipped layouts and
    # mods: Herdr owns and writes those files. Link only our files so the
    # app can still write jsconfig.json and .d.ts beside the mod.
    xdg.configFile = {
      "herdr-app/keys.json".source = ./keys.json;
      "herdr-app/settings.json".source = ./settings.json;
      "herdr-app/themes/rose-pine.json".source = ./rose-pine.json;
      "herdr-app/layouts/work-items.json".source = ./layouts/work-items.json;
      "herdr-app/layouts/work-items.svg".source = ./layouts/work-items.svg;
      "herdr-app/mods/work-items/mod.json".source = ./mods/work-items/mod.json;
      "herdr-app/mods/work-items/main.js".source = ./mods/work-items/main.js;
      "herdr-app/mods/work-agents/mod.json".source = ./mods/work-agents/mod.json;
      "herdr-app/mods/work-agents/main.js".source = ./mods/work-agents/main.js;
      "herdr-app/mods/subscription-usage/mod.json".source = ./mods/subscription-usage/mod.json;
      "herdr-app/mods/subscription-usage/main.js".source = ./mods/subscription-usage/main.js;
      # From github:atuinsh/herdr-atuin-threads@6e2786d. Needs atuin threads;
      # see programs.atuin in users/jordangarrison/home.nix.
      "herdr-app/mods/atuin-threads/mod.json".source = ./mods/atuin-threads/mod.json;
      "herdr-app/mods/atuin-threads/main.js".source = ./mods/atuin-threads/main.js;
      "herdr-app/mods/atuin-threads/threads.svg".source = ./mods/atuin-threads/threads.svg;
      # Space folders (inputs.herdr-space-folders; `nix flake update
      # herdr-space-folders` to update). Herdr's main layout with a spaces
      # list that has folders. The mod keeps its folders in
      # ~/.config/herdr-space-folders.json; we do not manage that file. Its
      # next/prev space keys are the layout:main-folders section of keys.json.
      "herdr-app/layouts/main-folders.json".source =
        "${inputs.herdr-space-folders}/layouts/main-folders.json";
      "herdr-app/mods/space-folders/mod.json".source =
        "${inputs.herdr-space-folders}/mods/space-folders/mod.json";
      "herdr-app/mods/space-folders/main.js".source =
        "${inputs.herdr-space-folders}/mods/space-folders/main.js";
      # main-issues: Herdr's main layout with the issues panel (copiedMods)
      # and its button.
      "herdr-app/layouts/main-issues.json".source = "${inputs.herdr-issues}/layouts/main-issues.json";
      # The jagpi layout, with `machine` on every jagpi-board block when the
      # daemon runs elsewhere (see jagpiLayout).
      "herdr-app/layouts/jagpi.json".source = jagpiLayout;
      "herdr-app/layouts/jagpi.svg".source = "${jagpiBoardSrc}/layouts/jagpi.svg";
    };

    # Herdr T3 layout (inputs.herdr-t3; `nix flake update herdr-t3` to update).
    # Copied, not linked: see install-herdr-t3.sh. This step owns the t3-*
    # mods and layouts/herdr-t3.*; local edits to them are replaced.
    home.activation.herdrT3 = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe installHerdrT3} ${inputs.herdr-t3} "${config.xdg.configHome}/herdr-app"
    '';

    # After linkGeneration, so the old generation's links are gone first.
    home.activation.herdrMods = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe installHerdrMods} "${config.xdg.configHome}/herdr-app" ${
        lib.escapeShellArgs (lib.mapAttrsToList (name: src: "${name}=${src}") copiedMods)
      }
    '';

    # Revive, part 1: pi records its session through this extension. A link
    # to the copied mod, as `revive.mjs install` would make: the extension
    # finds the engine beside its real path.
    home.file.".pi/agent/extensions/herdr-revive.ts" = lib.mkIf (config.programs.pi.enable or false) {
      source = config.lib.file.mkOutOfStoreSymlink "${reviveDir}/pi/revive.ts";
    };

    # Revive, part 2: a recovered shell resumes the session at its first
    # prompt. Last in .zshrc, where `revive.mjs install` would put it.
    programs.zsh.initContent = lib.mkIf config.programs.zsh.enable (
      lib.mkOrder 2000 ''
        # herdr-revive: resume the agent this herdr terminal lost to a reboot.
        source ${reviveZshBlock}
      ''
    );

    # Revive, part 3: Claude Code records its session through SessionStart and
    # SessionEnd hooks. Not declared in programs.claude-code.settings: that
    # merge replaces arrays, which would drop the other tools' hooks. Revive's
    # installer adds only its own entries and leaves the rest. It changes
    # nothing when they are there, and backs up settings.json once to
    # settings.json.revive-backup. The shell block, pi and the agents we do
    # not want recorded are skipped here.
    home.activation.herdrReviveClaudeHooks = lib.mkIf (config.programs.claude-code.enable or false) (
      lib.hm.dag.entryAfter [ "herdrMods" "claudeCodeSettingsMerge" ] ''
        run ${lib.getExe pkgs.nodejs} ${lib.escapeShellArg "${reviveDir}/revive.mjs"} install \
          --no-shell --no-pi --no-omp --no-codex --no-droid --no-cursor \
          || warnEcho "herdr-revive: could not add its Claude Code hooks; run the install above by hand"
      ''
    );
  };
}
