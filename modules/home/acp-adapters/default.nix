{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  cfg = config.programs.acp-adapters;
  llmAgents = pkgs.llm-agents or { };

  llmPackage = name: if builtins.hasAttr name llmAgents then builtins.getAttr name llmAgents else null;

  adapterPackageOption =
    {
      adapterName,
      llmPackageName,
      defaultPackage,
    }:
    mkOption {
      type = types.nullOr types.package;
      default = defaultPackage;
      defaultText = literalExpression "pkgs.llm-agents.${llmPackageName} or null";
      description = ''
        Package providing the ${adapterName} ACP adapter binary. Defaults to
        pkgs.llm-agents.${llmPackageName} when that package exists, but may be
        overridden with a nixpkgs package, local package, or future flake output.
      '';
    };

  adapterCommandOption =
    {
      adapterName,
      defaultCommand,
    }:
    mkOption {
      type = types.str;
      default = defaultCommand;
      description = ''
        Command name for the ${adapterName} ACP adapter binary. This option is
        informational for consumers such as Doom Emacs configuration; the module
        installs packages but does not generate wrappers.
      '';
    };

  enabledAdapterPackages =
    optional (cfg.claude.enable && cfg.claude.package != null) cfg.claude.package
    ++ optional (cfg.codex.enable && cfg.codex.package != null) cfg.codex.package
    ++ optional (cfg.pi.enable && cfg.pi.package != null) cfg.pi.package;
in
{
  options.programs.acp-adapters = {
    enable = mkEnableOption "ACP adapter binaries for agent clients";

    claude = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install the Claude ACP adapter.";
      };

      package = adapterPackageOption {
        adapterName = "Claude";
        llmPackageName = "claude-code-acp";
        defaultPackage = llmPackage "claude-code-acp";
      };

      command = adapterCommandOption {
        adapterName = "Claude";
        defaultCommand = "claude-agent-acp";
      };
    };

    codex = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install the Codex ACP adapter.";
      };

      package = adapterPackageOption {
        adapterName = "Codex";
        llmPackageName = "codex-acp";
        defaultPackage = llmPackage "codex-acp";
      };

      command = adapterCommandOption {
        adapterName = "Codex";
        defaultCommand = "codex-acp";
      };
    };

    pi = {
      enable = mkOption {
        type = types.bool;
        default = llmPackage "pi-acp" != null;
        defaultText = literalExpression "pkgs.llm-agents ? pi-acp";
        description = ''
          Whether to install the Pi ACP adapter. This defaults to true only when
          pkgs.llm-agents.pi-acp exists, because the current llm-agents input may
          not expose a Pi ACP package yet.
        '';
      };

      package = adapterPackageOption {
        adapterName = "Pi";
        llmPackageName = "pi-acp";
        defaultPackage = llmPackage "pi-acp";
      };

      command = adapterCommandOption {
        adapterName = "Pi";
        defaultCommand = "pi-acp";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.claude.enable && cfg.claude.package == null);
        message = "programs.acp-adapters.claude.enable is true, but no Claude ACP package is available. Set programs.acp-adapters.claude.package or expose pkgs.llm-agents.claude-code-acp.";
      }
      {
        assertion = !(cfg.codex.enable && cfg.codex.package == null);
        message = "programs.acp-adapters.codex.enable is true, but no Codex ACP package is available. Set programs.acp-adapters.codex.package or expose pkgs.llm-agents.codex-acp.";
      }
      {
        assertion = !(cfg.pi.enable && cfg.pi.package == null);
        message = "programs.acp-adapters.pi.enable is true, but no Pi ACP package is available. Set programs.acp-adapters.pi.package or expose pkgs.llm-agents.pi-acp.";
      }
    ];

    home.packages = enabledAdapterPackages;
  };
}
