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

  baseConfigFile = yamlFormat.generate "tea-config.yml" teaConfig;

  # Check if any login uses tokenFile
  hasTokenFiles = any (login: login.tokenFile != null) (attrValues cfg.logins);

  # Build the activation script to inject tokens from files
  tokenInjectionScript = concatStringsSep "\n" (mapAttrsToList (name: login:
    optionalString (login.tokenFile != null) ''
      if [ -f "${login.tokenFile}" ]; then
        token=$(cat "${login.tokenFile}")
        ${pkgs.yq-go}/bin/yq -i '(.logins[] | select(.name == "${name}")).token = "'"$token"'"' "$config_dir/config.yml"
      else
        echo "Warning: tea tokenFile ${login.tokenFile} not found for login '${name}'" >&2
      fi
    ''
  ) cfg.logins);

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
          API token for authentication.
          Warning: this value will be stored in the world-readable Nix store.
          Prefer tokenFile to keep the token out of the store.
        '';
      };

      tokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Path to a file containing the API token.
          Read at activation time so the token never enters the Nix store.
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

    # If no logins use tokenFile, manage config declaratively via xdg.configFile
    xdg.configFile."tea/config.yml" = mkIf (cfg.logins != { } && !hasTokenFiles) {
      source = baseConfigFile;
    };

    # If any login uses tokenFile, copy base config and inject tokens at activation time
    home.activation.teaConfig = mkIf (cfg.logins != { } && hasTokenFiles)
      (hm.dag.entryAfter [ "writeBoundary" ] ''
        config_dir="${config.xdg.configHome}/tea"
        mkdir -p "$config_dir"
        cp --no-preserve=mode ${baseConfigFile} "$config_dir/config.yml"
        chmod 600 "$config_dir/config.yml"
        ${tokenInjectionScript}
      '');
  };
}
