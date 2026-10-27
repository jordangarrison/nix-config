# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Additional drives
  # ──────────────────────────────────────────────────────────────────
  # hubble - Seagate Backup Plus Drive (NTFS, 931.5G) - archives/backup
  fileSystems."/mnt/hubble" = {
    device = "/dev/disk/by-uuid/06FE60D3FE60BD15";
    fsType = "ntfs3";
    options = [
      "rw"
      "uid=1000"
      "gid=100"
      "dmask=022"
      "fmask=133"
      "nofail"
      "force" # volume has dirty flag from previous Windows use
    ];
  };

  # apollo - New NVMe SSD (1TB) - fast storage for VMs and data layers
  # TODO: Install drive, format as ext4, then uncomment and set UUID
  #   sudo mkfs.ext4 -L apollo /dev/nvmeXn1p1
  #   blkid /dev/nvmeXn1p1  # get UUID
  # fileSystems."/mnt/apollo" = {
  #   device = "/dev/disk/by-uuid/REPLACE-WITH-UUID";
  #   fsType = "ext4";
  #   options = [ "nofail" ];
  # };

  # gemini - Former BitLocker drive (232.4G) - smaller supportive storage
  # TODO: Wipe and reformat once BitLocker data is recovered (or abandoned)
  #   sudo mkfs.ext4 -L gemini /dev/sda2
  #   blkid /dev/sda2  # get UUID
  # fileSystems."/mnt/gemini" = {
  #   device = "/dev/disk/by-uuid/REPLACE-WITH-UUID";
  #   fsType = "ext4";
  #   options = [ "nofail" ];
  # };

  # Intel WiFi AX200 stability improvements
  # Disables problematic WiFi 6 features and power saving that cause disconnections
  boot.extraModprobeConfig = ''
    options iwlwifi 11n_disable=8 power_save=0 swcrypto=1
  '';

  networking.hostName = "endeavour"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # NetworkManager WiFi stability settings
  networking.networkmanager.wifi = {
    # Disable power saving on WiFi interfaces
    powersave = false;
    # Prefer 5GHz networks when available
    scanRandMacAddress = false;
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Endeavour-specific display manager settings
  services.displayManager.autoLogin.enable = false;

  # Enable remote desktop services
  services.xrdp = {
    enable = false;
    defaultWindowManager = "gnome-session";
  };

  systemd.services."gnome-remote-desktop".wantedBy = [ "graphical.target" ];
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Enable Logitech Unifying Receiver (endeavour-specific hardware)
  hardware.logitech.wireless.enable = true;
  programs.solaar.enable = true;

  # User configuration now handled by user modules in flake.nix

  # Endeavour-specific system packages
  environment.systemPackages = with pkgs;
    [
      # Para Gnome
      shotwell

      # Windows virtualized
      # winboat # 2025-11-18 Currently broken
    ];

  # Personal coding agent, running as Jordan. Enrollment + the root-owned enabled marker are
  # required before it connects to Slack; see docs/runbooks/hermes.md.
  services.hermes = {
    enable = true;
    user = "jordangarrison";
    allowedUsers = [ "UQ69UGHKM" ]; # Jordan's work Slack member ID
    instructions = builtins.readFile ../../users/jordangarrison/agents/AGENTS.md;
    herdrIntegration.enable = true;
    model = "gpt-6.1-sol";
    plugins.conduit_push = pkgs.callPackage ../../packages/hermes-conduit-notifier { };
    # The shared agent MCP list (programs.mcp in users/jordangarrison/home.nix).
    # The Executor gateways are OAuth with dynamic client registration.
    mcpServers = pkgs.lib.mapAttrs (_: s:
      if s.command != null
      then { inherit (s) command args; }
      else { inherit (s) url; auth = "oauth"; }
    ) config.home-manager.users.jordangarrison.programs.mcp.servers;
    # JordanBot: one Slack app and one default profile for every channel and
    # DM. Hermes owns config.yaml, .env and SOUL.md (edit them in Desktop);
    # these are only the first config's Slack settings. See docs/runbooks/hermes.md.
    slack.enableMarker = "/var/lib/hermes-secrets/jordanbot-enabled";
    seedSettings = {
      platforms.slack = {
        enabled = true;
        home_channel = { platform = "slack"; chat_id = "D0CCDQ1JBNY"; name = "JordanBot DM"; };
        extra = {
          allowed_channels = [ ]; # any channel JordanBot is in
          require_mention = true; # a new conversation needs @JordanBot...
          strict_mention = false; # ...then it follows that thread
          thread_require_mention = false;
          reactions = true; # :eyes: while working, then a check or cross
          reaction_triggers = [ "jordanbot" ];
          rich_blocks = true;
        };
      };
      display.platforms.slack.memory_notifications = "off";
    };
    desktop = {
      enable = true;
      publicHost = "hermes.jordangarrison.dev";
    };
  };
  users.jordangarrison.apps.hermes-desktop.enable = true;
  # Interactive CLI chats use the dashboard profile's stored state/credentials.
  # This does not promise simultaneous live-session ownership across clients.
  # `command hermes` still reaches the separate ~/.hermes installation.
  home-manager.users.jordangarrison.home.shellAliases.hermes = "hermes-service";

  # DNS points at Endeavour's tailnet IP. The source ACL is still required:
  # the host firewall is off, and a LAN client can spoof the HTTP Host header.
  security.acme.certs."hermes.jordangarrison.dev" = {
    group = "nginx";
    dnsResolver = "1.1.1.1:53";
  };
  services.nginx.virtualHosts."hermes.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "hermes.jordangarrison.dev";
    extraConfig = ''
      # WS tickets and native sign-in codes must not end up in access logs.
      access_log off;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.hermes.desktop.port}";
      proxyWebsockets = true;
      # Set an authoritative client IP, not a caller-supplied forwarding chain.
      recommendedProxySettings = false;
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        add_header X-Robots-Tag "noindex, nofollow" always;
      '';
    };
  };

  # Private tailnet access to bb; the reusable service stays loopback-only.
  security.acme.certs."bb.jordangarrison.dev".group = "nginx";
  services.nginx.virtualHosts."bb.jordangarrison.dev" = {
    forceSSL = true;
    useACMEHost = "bb.jordangarrison.dev";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.bb.port}";
      proxyWebsockets = true;
      extraConfig = ''
        allow 127.0.0.1;
        allow ::1;
        allow 100.64.0.0/10;
        allow fd7a:115c:a1e0::/48;
        deny all;
        proxy_read_timeout 3600s;
        proxy_buffering off;
      '';
    };
  };

  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
