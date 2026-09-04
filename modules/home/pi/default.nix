# Pi's settings.json is mutable: pi itself writes it at runtime (model picker,
# `pi install`), so this module owns the file as a regular file and deep-merges
# the declarative values into it on activation instead of linking the store.
#
# Rolling back to a generation from before that change fails on a machine that
# already has `~/.pi/agent/settings.json.backup`: Home Manager wants to back up
# the now-unmanaged regular file and refuses to clobber the existing backup
# (check-link-targets.sh). Remove that stale backup first, then roll back.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.pi;
  jsonFormat = pkgs.formats.json { };
  settingsPath = "${config.home.homeDirectory}/.pi/agent/settings.json";

  validateManagedSettingsSymlink = path: ''
    linkTarget="$(${getExe' pkgs.coreutils "readlink"} ${escapeShellArg path})"
    case "$linkTarget" in
      /nix/store/*-home-manager-files/.pi/agent/settings.json) ;;
      *)
        echo "Refusing to replace non-Home-Manager settings symlink: ${path} -> $linkTarget" >&2
        exit 1
        ;;
    esac
  '';

  # Both writers run in a subshell: Home Manager installs its own EXIT trap for
  # the new generation's GC root right before the activation commands, so
  # clearing a local trap here would disarm that cleanup for everything after.
  writeSettingsAtomically = path: source: ''
    (
      piSettingsTmp="$(${getExe' pkgs.coreutils "mktemp"} \
        "$(dirname ${escapeShellArg path})/.settings.json.home-manager.XXXXXX")"
      trap '${getExe' pkgs.coreutils "rm"} -f "$piSettingsTmp"' EXIT
      ${source}
      ${getExe' pkgs.coreutils "mv"} -f "$piSettingsTmp" ${escapeShellArg path}
    )
  '';

  migrateManagedSettingsSymlink = path: ''
    if [ -L ${escapeShellArg path} ]; then
      ${validateManagedSettingsSymlink path}

      if [ ! -e ${escapeShellArg path} ]; then
        # Verified above as Home Manager's own link, and it can only have held
        # declarative values that the merge re-applies moments later, so drop
        # it rather than wedging this and every later activation.
        if [[ -v DRY_RUN ]]; then
          echo "Would remove dangling Home Manager settings symlink: ${path} -> $linkTarget"
        else
          ${getExe' pkgs.coreutils "rm"} -f ${escapeShellArg path}
        fi
      elif ! ${getExe pkgs.jq} -e . ${escapeShellArg path} >/dev/null; then
        echo "Refusing to migrate invalid JSON from ${path}" >&2
        exit 1
      elif [[ -v DRY_RUN ]]; then
        echo "Would migrate Home Manager settings symlink to a writable file: ${path}"
      else
        ${writeSettingsAtomically path ''cat ${escapeShellArg path} > "$piSettingsTmp"''}
      fi
      unset linkTarget
    fi
  '';

  mergeMutableJson = path: staticSettings: ''
    if [ -L ${escapeShellArg path} ]; then
      ${validateManagedSettingsSymlink path}
    fi

    if [[ -v DRY_RUN ]]; then
      echo "Would deep-merge declarative Pi settings into ${path}"
    else
      mkdir -p "$(dirname ${escapeShellArg path})"

      # A partial write from pi leaves an empty or non-object file; treat the
      # empty case as "no runtime settings yet" and refuse the rest by name,
      # rather than letting jq fail mid-merge with an anonymous error.
      if [ -s ${escapeShellArg path} ]; then
        if ! dynamic="$(${getExe pkgs.jq} -c \
          'if type == "object" then . else halt_error(1) end' ${escapeShellArg path})"; then
          echo "Refusing to overwrite invalid or non-object JSON in ${path}" >&2
          exit 1
        fi
      else
        dynamic='{}'
      fi

      static="$(cat ${escapeShellArg staticSettings})"
      merged="$(${getExe pkgs.jq} -n ${escapeShellArg "$dynamic * $static"} \
        --argjson dynamic "$dynamic" \
        --argjson static "$static")"

      ${writeSettingsAtomically path ''printf '%s\n' "$merged" > "$piSettingsTmp"''}
      unset dynamic static merged
    fi
    unset linkTarget
  '';

  # One-shot cleanup of extensions the retired Orca module used to write into
  # this same mutable directory. Drop this list (and its activation entry) after
  # 2026-11-01, by which point every machine has activated at least once.
  obsoleteOrcaExtensions = [
    "orca-agent-status.ts"
    "orca-prefill.ts"
    "orca-titlebar-spinner.ts"
  ];

  removeObsoleteOrcaExtension = name: ''
    orcaExtension=${escapeShellArg "${config.home.homeDirectory}/.pi/agent/extensions/${name}"}
    if [ -f "$orcaExtension" ] && [ ! -L "$orcaExtension" ] \
      && ${getExe pkgs.gnugrep} -Fqx '// @orca-managed-pi-extension' "$orcaExtension"; then
      if [[ -v DRY_RUN ]]; then
        echo "Would remove obsolete Orca-managed Pi extension: $orcaExtension"
      else
        ${getExe' pkgs.coreutils "rm"} -f "$orcaExtension"
      fi
    fi
    unset orcaExtension
  '';

  fileEntryType = types.submodule {
    options = {
      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Inline file contents to write.";
      };

      source = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Source file to link into the pi agent directory.";
      };
    };
  };

  resourceOptions = kind: {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to manage pi ${kind}.";
    };

    useDefaults = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to include the module-provided default pi ${kind}.";
    };

    disable = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Default pi ${kind} filenames to omit.";
    };

    files = mkOption {
      type = types.attrsOf fileEntryType;
      default = { };
      description = "Additional or replacement pi ${kind} files keyed by filename.";
    };
  };

  defaultSettings = {
    defaultThinkingLevel = "medium";
    collapseChangelog = true;
    enableInstallTelemetry = false;
    enableSkillCommands = true;
    quietStartup = false;
    treeFilterMode = "default";
  };

  defaultKeybindings = {
    "tui.input.newLine" = [
      "shift+enter"
      "ctrl+j"
    ];
  };

  defaultPrompts = {
    "research.md".source = ./prompts/research.md;
    "review.md".source = ./prompts/review.md;
    "nixos-change.md".source = ./prompts/nixos-change.md;
  };

  defaultThemes = {
    "jordangarrison.json".source = ./themes/jordangarrison.json;
  };

  defaultExtensions = {
    "claude-subscription-usage.ts".source = ./extensions/claude-subscription-usage.ts;
    "protected-paths.ts".source = ./extensions/protected-paths.ts;
    "status-line.ts".source = ./extensions/status-line.ts;
  };

  resolveResources =
    defaults: resourceCfg:
    if !resourceCfg.enable then
      { }
    else
      (if resourceCfg.useDefaults then removeAttrs defaults resourceCfg.disable else { })
      // resourceCfg.files;

  promptFiles = resolveResources defaultPrompts cfg.prompts;
  themeFiles = resolveResources defaultThemes cfg.themes;
  extensionFiles = resolveResources defaultExtensions cfg.extensions;

  fileToHomeFile =
    directory: name: file:
    nameValuePair ".pi/agent/${directory}/${name}" (
      if (file.text or null) != null then { inherit (file) text; } else { inherit (file) source; }
    );

  resourceHomeFiles = directory: files: listToAttrs (mapAttrsToList (fileToHomeFile directory) files);

  settingsWithTheme =
    recursiveUpdate defaultSettings cfg.settings
    // optionalAttrs (cfg.themes.enable && cfg.themes.active != null) {
      theme = cfg.themes.active;
    };

  keybindings = recursiveUpdate defaultKeybindings cfg.keybindings;

  settingsFile = jsonFormat.generate "pi-settings.json" settingsWithTheme;
  keybindingsFile = jsonFormat.generate "pi-keybindings.json" keybindings;
  modelsFile = jsonFormat.generate "pi-models.json" cfg.models;

  fileEntryAssertions =
    kind: files:
    mapAttrsToList (name: file: {
      assertion = (file.text != null) != (file.source != null);
      message = "programs.pi.${kind}.files.${name} must set exactly one of text or source.";
    }) files;

  activeThemeFile = if cfg.themes.active == null then null else "${cfg.themes.active}.json";
in
{
  options.programs.pi = {
    enable = mkEnableOption "pi coding agent";

    package = mkOption {
      type = types.package;
      default = pkgs.llm-agents.pi;
      defaultText = literalExpression "pkgs.llm-agents.pi";
      description = "The pi package to install.";
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Declarative settings deep-merged into the writable
        {file}`~/.pi/agent/settings.json` on activation. Declarative values
        take precedence over values already in the file.

        Two consequences of the merge, since pi also writes this file:

        - Objects merge key by key, but arrays are replaced wholesale. Setting
          `settings.packages` therefore discards anything `pi install` added to
          that array at the next activation. Leave an array undeclared to let
          pi own it.
        - The merge only adds and overwrites; it never prunes. Removing a key
          here leaves the last written value in the file, so drop it from the
          file by hand when a declarative setting is retired.
      '';
    };

    keybindings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = "Keybindings written to ~/.pi/agent/keybindings.json.";
    };

    models = mkOption {
      type = jsonFormat.type;
      default = { };
      example = literalExpression ''
        {
          providers.ollama = {
            baseUrl = "http://127.0.0.1:11434/v1";
            api = "openai-completions";
            apiKey = "ollama";
            models = [ { id = "qwen3.6:35b-a3b-coding"; } ];
          };
        }
      '';
      description = ''
        Custom providers and models written to {file}`~/.pi/agent/models.json`
        — local servers such as Ollama, vLLM or LM Studio, and proxies. See
        `docs/models.md` in the pi package for the schema.

        Unlike settings.json, pi only ever reads this file, so it is linked
        read-only from the store rather than merged on activation. Leaving
        this unset leaves the file unmanaged.
      '';
    };

    prompts = mkOption {
      type = types.submodule {
        options = resourceOptions "prompt templates";
      };
      default = { };
      description = "Prompt template files written to ~/.pi/agent/prompts/.";
    };

    themes = mkOption {
      type = types.submodule {
        options = resourceOptions "themes" // {
          active = mkOption {
            type = types.nullOr types.str;
            default = "jordangarrison";
            description = ''
              Active pi theme name. When set, this module writes the value to
              settings.theme and expects a managed theme file named <active>.json.
            '';
          };
        };
      };
      default = { };
      description = "Theme files written to ~/.pi/agent/themes/.";
    };

    extensions = mkOption {
      type = types.submodule {
        options = resourceOptions "extensions";
      };
      default = { };
      description = "Extension files written to ~/.pi/agent/extensions/.";
    };

    tmux = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to add pi-friendly tmux extended key settings when tmux is enabled.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions =
      fileEntryAssertions "prompts" cfg.prompts.files
      ++ fileEntryAssertions "themes" cfg.themes.files
      ++ fileEntryAssertions "extensions" cfg.extensions.files
      ++ [
        {
          assertion = !(cfg.themes.enable && cfg.themes.active != null && cfg.settings ? theme);
          message = "Set programs.pi.themes.active or programs.pi.settings.theme, not both.";
        }
        {
          assertion = !(cfg.themes.enable && cfg.themes.active != null) || hasAttr activeThemeFile themeFiles;
          message = "programs.pi.themes.active is '${cfg.themes.active}', but no managed theme file named '${activeThemeFile}' exists.";
        }
      ];

    home.packages = [ cfg.package ];

    home.activation = {
      piSettingsSymlinkMigration = hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] (
        migrateManagedSettingsSymlink settingsPath
      );

      piSettingsActivation = hm.dag.entryAfter [ "linkGeneration" ] (
        mergeMutableJson settingsPath settingsFile
      );

      piRemoveObsoleteOrcaExtensions = hm.dag.entryAfter [ "linkGeneration" ] (
        concatMapStringsSep "\n" removeObsoleteOrcaExtension obsoleteOrcaExtensions
      );
    };

    home.file = {
      ".pi/agent/keybindings.json".source = keybindingsFile;
    }
    // optionalAttrs (cfg.models != { }) {
      ".pi/agent/models.json".source = modelsFile;
    }
    // resourceHomeFiles "prompts" promptFiles
    // resourceHomeFiles "themes" themeFiles
    // resourceHomeFiles "extensions" extensionFiles;

    programs.tmux.extraConfig = mkIf (cfg.tmux.enable && config.programs.tmux.enable) (mkAfter ''
      set -g extended-keys on
      set -g extended-keys-format csi-u
    '');
  };
}
