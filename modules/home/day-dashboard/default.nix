{ config, lib, pkgs, ... }:

let
  cfg = config.services.day-dashboard;
in
{
  # The day-dashboard generator as a systemd **user** service + timer. It runs
  # inside the graphical session so the collectors can reach the user's login
  # keyring — which is where both the Pi MCP OAuth tokens (Slack/Linear) and the
  # `gws` Google credentials (email/calendar) live. A bare system service can't
  # see that keyring, so this deliberately lives in Home Manager, not NixOS.
  #
  # The matching system module (modules/nixos/day-dashboard.nix) owns the served
  # directory and the private nginx vhost.
  options.services.day-dashboard = {
    enable = lib.mkEnableOption "hourly personal day-dashboard generator (user service)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.day-dashboard;
      defaultText = lib.literalExpression "pkgs.day-dashboard";
      description = "The day-dashboard package to run.";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "openai-codex/gpt-5.6-sol";
      description = ''
        Stronger model for the final synthesis/aggregation pass (merging related
        items, prioritizing). Runs once per refresh and is cached, so its cost is
        bounded. `claude-bridge/claude-opus-5` also works.
      '';
    };

    mcpModel = lib.mkOption {
      type = lib.types.str;
      default = "openai-codex/gpt-5.6-luna";
      description = "Cheap/fast model the per-source MCP collectors use to extract data.";
    };

    sources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "calendar" "email" "notes" "slack" "linear" "github" "rootly" "confluence" ];
      description = "Which collectors to run (each degrades gracefully).";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/day-dashboard";
      description = "Base state dir (must match services.day-dashboard on the system side).";
    };

    dismissPort = lib.mkOption {
      type = lib.types.port;
      default = 8846;
      description = ''
        localhost port for the ✕ dismiss handler. The system module proxies
        /dismiss on the private vhost to this port; keep the two in sync.
      '';
    };

    mcpConfig = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.config/mcp/mcp.json";
      description = "MCP config the Slack/Linear collectors drive via the Pi CLI.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 06..21:00:00";
      description = "systemd OnCalendar expression (hourly 06:00–21:00).";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        DAY_DASHBOARD_CONFLUENCE_BASE = "https://flocasts.atlassian.net/wiki";
      };
      description = "Extra environment for the generator (e.g. Confluence base URL).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.day-dashboard = {
      Unit = {
        Description = "Generate the private personal day dashboard";
        # Only run with a live graphical session — that is what unlocks the
        # login keyring the collectors depend on.
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        # %t = XDG_RUNTIME_DIR; the login keyring/D-Bus session live on this bus.
        Environment = [
          "DAY_DASHBOARD_STATE_DIR=${cfg.stateDir}"
          "DAY_DASHBOARD_MODEL=${cfg.model}"
          "DAY_DASHBOARD_MCP_MODEL=${cfg.mcpModel}"
          # Comma-joined: systemd Environment= would otherwise split a
          # space-separated value into bogus assignments.
          "DAY_DASHBOARD_SOURCES=${lib.concatStringsSep "," cfg.sources}"
          "DAY_DASHBOARD_MCP_CONFIG=${cfg.mcpConfig}"
          "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus"
        ] ++ lib.mapAttrsToList (k: v: "${k}=${v}") cfg.environment;
        ExecStart = lib.getExe cfg.package;
        # A slow source or model must not wedge the timer for the whole hour.
        # 10min headroom: three sequential MCP collectors (Slack/Linear/Rootly)
        # plus meeting-note doc exports can add up on a fully-fresh run; the
        # cache keeps most later runs far shorter.
        TimeoutStartSec = "10min";
        Nice = 10;
      };
    };

    # Long-running handler for the dashboard's ✕ dismiss links. No keyring
    # needed (it only reads/writes JSON under the state dir and re-renders), so
    # it runs under the plain user manager rather than the graphical session.
    systemd.user.services.day-dashboard-dismiss = {
      Unit.Description = "Day dashboard dismiss handler (localhost)";
      Service = {
        Environment = [
          "DAY_DASHBOARD_STATE_DIR=${cfg.stateDir}"
          "DAY_DASHBOARD_DISMISS_PORT=${toString cfg.dismissPort}"
        ];
        ExecStart = "${cfg.package}/bin/day-dashboard-dismiss-server";
        Restart = "on-failure";
        RestartSec = "5s";
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.timers.day-dashboard = {
      Unit.Description = "Hourly (06:00–21:00) day dashboard refresh";
      Timer = {
        OnCalendar = cfg.schedule;
        OnActiveSec = "2min"; # first run shortly after the session comes up
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
