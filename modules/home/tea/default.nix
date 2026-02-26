{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.programs.tea;
  yamlFormat = pkgs.formats.yaml { };

  # Map a login attrset entry to the tea config.yml format
  # Only include non-default values for a cleaner config file
  loginToYaml = name: login:
    { inherit name; inherit (login) url user; }
    // optionalAttrs login.default { inherit (login) default; }
    // optionalAttrs (login.token != "") { inherit (login) token; }
    // optionalAttrs (login.sshHost != "") { ssh_host = login.sshHost; }
    // optionalAttrs (login.sshKey != "") { ssh_key = login.sshKey; }
    // optionalAttrs login.sshAgent { ssh_agent = login.sshAgent; }
    // optionalAttrs login.insecure { inherit (login) insecure; };

  # Build the full tea configuration
  teaConfig = {
    logins = mapAttrsToList loginToYaml cfg.logins;
    preferences = cfg.settings;
  };

  loginSubmodule = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = "URL of the Gitea/Forgejo instance.";
      };

      user = mkOption {
        type = types.str;
        description = "Username for this login.";
      };

      default = mkOption {
        type = types.bool;
        default = false;
        description = "Whether this is the default login.";
      };

      token = mkOption {
        type = types.str;
        default = "";
        description = ''
          API token for authentication. Optional if using SSH.
          Warning: this value will be stored in the world-readable Nix store.
          Prefer SSH authentication or manage the token outside of Nix.
        '';
      };

      sshHost = mkOption {
        type = types.str;
        default = "";
        description = "SSH hostname for git operations.";
      };

      sshKey = mkOption {
        type = types.str;
        default = "";
        description = "Path to SSH private key.";
      };

      sshAgent = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use the SSH agent for authentication.";
      };

      insecure = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to skip TLS verification.";
      };
    };
  };
in
{
  options.programs.tea = {
    enable = mkEnableOption "tea, the Gitea/Forgejo CLI tool";

    package = mkOption {
      type = types.package;
      default = pkgs.tea;
      defaultText = literalExpression "pkgs.tea";
      description = "The tea package to install.";
    };

    logins = mkOption {
      type = types.attrsOf loginSubmodule;
      default = { };
      description = ''
        Attrset of tea logins. The attribute name becomes the login name
        in the tea configuration file.
      '';
    };

    settings = mkOption {
      type = yamlFormat.type;
      default = {
        editor = false;
        flag_defaults = {
          remote = "";
        };
      };
      description = "Tea preferences written to the config file.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."tea/config.yml" = mkIf (cfg.logins != { }) {
      source = yamlFormat.generate "tea-config.yml" teaConfig;
    };
  };
}
