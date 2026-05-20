{ config, lib, pkgs, ... }:

let
  user = "jordangarrison";
  home = "/home/${user}";
  dataDir = "${home}/.agentsview";
  port = 8080;
  host = "agentsview.jordangarrison.dev";
in
{
  systemd.services.agentsview = {
    description = "agentsview - local viewer and analytics for AI agent sessions";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      AGENTSVIEW_DATA_DIR = dataDir;
      CLAUDE_PROJECTS_DIR = "${home}/.claude/projects";
      CODEX_SESSIONS_DIR = "${home}/.codex/sessions";
      HOME = home;
    };

    serviceConfig = {
      User = user;
      Group = "users";
      ExecStart = ''
        ${pkgs.llm-agents.agentsview}/bin/agentsview serve \
          --host 127.0.0.1 \
          --port ${toString port} \
          --no-browser \
          --no-update-check \
          --public-url https://${host}
      '';
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  security.acme.certs.${host} = {
    group = "nginx";
  };

  services.nginx.virtualHosts.${host} = {
    forceSSL = true;
    useACMEHost = host;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
    };
  };
}
