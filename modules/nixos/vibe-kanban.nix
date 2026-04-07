{ config, lib, pkgs, ... }:

{
  # Systemd service for Vibe Kanban
  systemd.services.vibe-kanban = {
    description = "Vibe Kanban - AI Agent Management Board";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    environment = {
      # Server configuration (binary reads PORT/HOST env vars, not CLI flags)
      PORT = "7780";
      HOST = "127.0.0.1";
      # Suppress browser auto-open in headless systemd context
      BROWSER = "true";
      # Allow WebSocket connections through the reverse proxy
      VK_ALLOWED_ORIGINS = "https://vibe-kanban.jordangarrison.dev";
      # Wayland display access for "open in editor" functionality
      WAYLAND_DISPLAY = "wayland-1";
      DISPLAY = ":0";
      XDG_RUNTIME_DIR = "/run/user/1000";
    };

    serviceConfig = {
      Type = "exec";
      User = "jordangarrison";
      Group = "users";
      WorkingDirectory = "/home/jordangarrison";
      ExecStart = "${pkgs.llm-agents.vibe-kanban}/bin/vibe-kanban";
      Restart = "on-failure";
      RestartSec = 5;

      # Prevent fd exhaustion from MCP clients, WebSockets, and Postgres
      LimitNOFILE = 65536;

      # Allow access to user's home for git repos, SSH keys, dev tools
      ProtectHome = false;
    };
  };

  # ACME certificate via Cloudflare DNS-01 (defaults from nginx.nix)
  security.acme.certs."vibe-kanban.jordangarrison.dev" = {
    group = "nginx";
  };

  # Nginx reverse proxy
  services.nginx.virtualHosts."vibe-kanban.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "vibe-kanban.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://localhost:7780";
      proxyWebsockets = true;
    };
  };
}
