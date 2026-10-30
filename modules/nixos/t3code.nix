{ config, lib, pkgs, utils, ... }:

# Personal coding server. Network policy belongs to the host's reverse proxy.
let
  cfg = config.services.t3code;
  home = config.users.users.${cfg.user}.home;
  group = config.users.users.${cfg.user}.group;
in
{
  options.services.t3code = {
    enable = lib.mkEnableOption "T3 Code web console and coding server";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Existing user whose projects and provider logins the server uses.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 3773;
      description = "Loopback HTTP/WebSocket port.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.local/share/t3code-server";
      defaultText = lib.literalExpression ''"''${config.users.users.''${config.services.t3code.user}.home}/.local/share/t3code-server"'';
      description = "Persistent T3 home, separate from the desktop's ~/.t3.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != "root";
        message = "services.t3code must run as a non-root user.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.dataDir && cfg.dataDir != "${home}/.t3";
        message = "services.t3code.dataDir must be absolute and separate from the desktop's ~/.t3.";
      }
    ];

    systemd.tmpfiles.settings."10-t3code".${cfg.dataDir}.d = {
      mode = "0700";
      user = cfg.user;
      inherit group;
    };

    systemd.services.t3code = {
      description = "T3 Code web console";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = utils.escapeSystemdExecArgs [ home cfg.dataDir ];
      path = [
        pkgs.llm-agents.t3code
        pkgs.git
        pkgs.openssh
        pkgs.bash
        "/run/wrappers"
        "/etc/profiles/per-user/${cfg.user}"
        "${home}/.nix-profile"
        "/run/current-system/sw"
      ];
      environment = {
        HOME = home;
        # Preserve the provider/tool PATH in shells spawned by agents.
        __NIXOS_SET_ENVIRONMENT_DONE = "1";
      };
      # This is the user's coding environment, not an isolated multi-user
      # service: agents need worktrees, credentials, Nix and development tools.
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = group;
        WorkingDirectory = home;
        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe pkgs.llm-agents.t3code)
          "serve"
          "--host" "127.0.0.1"
          "--port" (toString cfg.port)
          "--base-dir" cfg.dataDir
        ];
        Restart = "on-failure";
        RestartSec = "5s";
        KillMode = "control-group";
        UMask = "0077";
        # `serve` prints a full-access pairing token/QR to stdout. Never put
        # those in the system journal; generate short-lived links on demand.
        StandardOutput = "null";
        StandardError = "journal";
      };
    };
  };
}
