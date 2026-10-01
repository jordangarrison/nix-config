{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.bb;
  providerPackages = {
    cursor = "cursor-agent";
    codex = "codex";
    pi = "pi";
    claude = "claude-code";
  };
  enabledProviders = lib.mapAttrsToList (name: _: cfg.providers.${name}.package) (
    lib.filterAttrs (name: _: cfg.providers.${name}.enable) providerPackages
  );
in
{
  options.services.bb = {
    enable = lib.mkEnableOption "bb agentic IDE and host daemon";

    package = lib.mkPackageOption pkgs [ "llm-agents" "bb-app" ] { };

    user = lib.mkOption {
      type = lib.types.str;
      example = "jordangarrison";
      description = "Existing NixOS user running bb and its coding agents. No account is created.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = config.users.users.${cfg.user}.group;
      defaultText = lib.literalExpression "config.users.users.<user>.group";
      description = "Primary group of the bb service.";
    };

    home = lib.mkOption {
      type = lib.types.path;
      default = config.users.users.${cfg.user}.home;
      defaultText = lib.literalExpression "config.users.users.<user>.home";
      description = "HOME used for repositories, Git/SSH and native provider configuration/credentials.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${cfg.home}/.bb";
      defaultText = lib.literalExpression ''"''${config.services.bb.home}/.bb"'';
      description = "Mutable bb state directory, created with mode 0700.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 38886;
      description = "bb web UI/API TCP port.";
    };

    bindHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Web UI/API bind address. Keep loopback for a separate Tailscale Serve proxy.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the web UI/API TCP port in the host firewall.";
    };

    providers = lib.mapAttrs (name: packageName: {
      enable = lib.mkEnableOption "the ${name} executable on bb's PATH";
      package = lib.mkPackageOption pkgs [ "llm-agents" packageName ] { };
    }) providerPackages;

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "with pkgs; [ nodejs ripgrep ]";
      description = "Additional providers and development tools available to bb and its child processes.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret environment variables. Values are stored in the Nix store; use environmentFile for secrets.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/bb";
      description = ''
        Absolute runtime path to a systemd EnvironmentFile containing credentials.
        Use a quoted string, not a Nix path literal; the file must not enter the
        Nix store. It must exist before bb starts (systemd reads it as root).
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional bb-app start arguments. Do not override module-managed flags or enable self-updates.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (
          arg:
          !(lib.elem arg [
            "--in-app-updates"
            "--auto-update"
          ])
        ) cfg.extraArgs;
        message = "services.bb: in-app/host-daemon updates must remain disabled; update the llm-agents flake input instead.";
      }
      {
        assertion = cfg.environmentFile == null || lib.hasPrefix "/" cfg.environmentFile;
        message = "services.bb.environmentFile must be an absolute runtime path.";
      }
    ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.tmpfiles.settings."10-bb".${cfg.dataDir}.d = {
      mode = "0700";
      user = cfg.user;
      group = cfg.group;
    };

    systemd.services.bb = {
      description = "bb agentic IDE";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = utils.escapeSystemdExecArgs [
        cfg.home
        cfg.dataDir
      ];

      # Keep declared providers first, but also expose the user's installed
      # tools. bb's daemon probes a login shell for PATH; NixOS's shell init
      # would otherwise replace this PATH with the global profile list.
      path =
        enabledProviders
        ++ cfg.extraPackages
        ++ [
          pkgs.git
          pkgs.openssh
          pkgs.bash
          "/run/wrappers"
          "/etc/profiles/per-user/${cfg.user}"
          "${cfg.home}/.nix-profile"
          "/run/current-system/sw"
        ];
      environment = cfg.environment // {
        HOME = cfg.home;
        __NIXOS_SET_ENVIRONMENT_DONE = "1";
        BB_HOST_DAEMON_AUTO_UPDATE = "0";
      };

      # Intentionally not sandboxed: bb must access the user's worktrees,
      # credentials and development tools, and spawn interactive agents.
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.home;
        ExecStart = utils.escapeSystemdExecArgs (
          [
            (lib.getExe cfg.package)
            "start"
            "--bundled"
            "--data-dir"
            cfg.dataDir
            "--server-port"
            (toString cfg.port)
            "--server-bind-host"
            cfg.bindHost
          ]
          ++ cfg.extraArgs
        );
        Restart = "on-failure";
        RestartSec = "5s";
        # Stop the whole process tree, including coding agents.
        KillMode = "control-group";
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
