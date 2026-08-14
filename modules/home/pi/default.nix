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

  migrateManagedSettingsSymlink = path: ''
    if [ -L ${escapeShellArg path} ]; then
      ${validateManagedSettingsSymlink path}

      if [ ! -e ${escapeShellArg path} ]; then
        echo "Cannot migrate dangling Home Manager settings symlink: ${path} -> $linkTarget" >&2
        exit 1
      fi
      if ! ${getExe pkgs.jq} -e . ${escapeShellArg path} >/dev/null; then
        echo "Refusing to migrate invalid JSON from ${path}" >&2
        exit 1
      fi

      if [[ -v DRY_RUN ]]; then
        echo "Would migrate Home Manager settings symlink to a writable file: ${path}"
      else
        piSettingsTmp="$(${getExe' pkgs.coreutils "mktemp"} \
          "$(dirname ${escapeShellArg path})/.settings.json.home-manager.XXXXXX")"
        trap '${getExe' pkgs.coreutils "rm"} -f "$piSettingsTmp"' EXIT
        cat ${escapeShellArg path} > "$piSettingsTmp"
        ${getExe' pkgs.coreutils "mv"} -f "$piSettingsTmp" ${escapeShellArg path}
        trap - EXIT
        unset piSettingsTmp
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

      if [ -e ${escapeShellArg path} ]; then
        if ! dynamic="$(${getExe pkgs.jq} -c . ${escapeShellArg path})"; then
          echo "Refusing to overwrite invalid JSON in ${path}" >&2
          exit 1
        fi
      else
        dynamic='{}'
      fi

      static="$(cat ${escapeShellArg staticSettings})"
      merged="$(${getExe pkgs.jq} -n ${escapeShellArg "$dynamic * $static"} \
        --argjson dynamic "$dynamic" \
        --argjson static "$static")"

      piSettingsTmp="$(${getExe' pkgs.coreutils "mktemp"} \
        "$(dirname ${escapeShellArg path})/.settings.json.home-manager.XXXXXX")"
      trap '${getExe' pkgs.coreutils "rm"} -f "$piSettingsTmp"' EXIT
      printf '%s\n' "$merged" > "$piSettingsTmp"
      ${getExe' pkgs.coreutils "mv"} -f "$piSettingsTmp" ${escapeShellArg path}
      trap - EXIT
      unset dynamic static merged piSettingsTmp
    fi
    unset linkTarget
  '';

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
    defaultThinkingLevel = "xhigh";
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
      '';
    };

    keybindings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = "Keybindings written to ~/.pi/agent/keybindings.json.";
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
    // resourceHomeFiles "prompts" promptFiles
    // resourceHomeFiles "themes" themeFiles
    // resourceHomeFiles "extensions" extensionFiles;

    programs.tmux.extraConfig = mkIf (cfg.tmux.enable && config.programs.tmux.enable) (mkAfter ''
      set -g extended-keys on
      set -g extended-keys-format csi-u
    '');
  };
}
