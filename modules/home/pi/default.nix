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
    defaultProvider = "openai-codex";
    defaultModel = "gpt-5.5";
    defaultThinkingLevel = "high";
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
      description = "Settings written to ~/.pi/agent/settings.json.";
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

    home.file = {
      ".pi/agent/settings.json".source = settingsFile;
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
