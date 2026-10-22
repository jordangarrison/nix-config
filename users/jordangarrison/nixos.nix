{ config, pkgs, lib, inputs, ... }:

let cfg = config.users.jordangarrison;
in {
  options.users.jordangarrison = {
    enable = lib.mkEnableOption "Jordan Garrison user account";

    username = lib.mkOption {
      type = lib.types.str;
      default = "jordangarrison";
      description = "Username for Jordan Garrison's account";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.username}";
      description = "Home directory path for Jordan";
    };

    swapSuperAlt = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Swap Super and Alt keys in GNOME";
    };

    apps = {
      # Communication
      zoom.enable = lib.mkEnableOption "Zoom video conferencing";
      session-desktop.enable = lib.mkEnableOption "Session encrypted messenger";
      slack.enable = lib.mkEnableOption "Slack messaging";
      discord.enable = lib.mkEnableOption "Discord";
      signal.enable = lib.mkEnableOption "Signal messenger";

      # Media & productivity
      spotify.enable = lib.mkEnableOption "Spotify music";
      obs.enable = lib.mkEnableOption "OBS Studio";
      obsidian.enable = lib.mkEnableOption "Obsidian and Logseq note-taking";
      todoist.enable = lib.mkEnableOption "Todoist task manager";
      calibre.enable = lib.mkEnableOption "Calibre e-book manager";
      nextcloud.enable = lib.mkEnableOption "Nextcloud client";
      deskflow.enable = lib.mkEnableOption "Deskflow KVM";

      # Editors & terminals
      zed.enable = lib.mkEnableOption "Zed editor";
      vscode.enable = lib.mkEnableOption "VSCode / Cursor editor";
      warp.enable = lib.mkEnableOption "Warp terminal (preview)";
      grok-bot.enable = lib.mkEnableOption "Grok Bot desktop agent";
      bb-desktop.enable = lib.mkEnableOption "BB desktop app";

      # Dev tools (heavy, built from source)
      codiff.enable = lib.mkEnableOption "Codiff local Git diff viewer";
      freelens.enable = lib.mkEnableOption "Freelens Kubernetes IDE";
      sidecar.enable = lib.mkEnableOption "Sidecar TUI for coding agents";
      codex.enable = lib.mkEnableOption "Codex and OpenCode LLM agents";
      grove.enable = lib.mkEnableOption "Grove workspace manager";
      google-cloud-sdk.enable = lib.mkEnableOption "Google Cloud SDK";
      azure-cli.enable = lib.mkEnableOption "Azure CLI";
      okta.enable = lib.mkEnableOption "Okta CLI client";
      plannotator.enable = lib.mkEnableOption "Plannotator agent plan/code review surface";
      pup.enable = lib.mkEnableOption "Datadog pup CLI";
      namespace.enable = lib.mkEnableOption "Namespace (namespace.so) nsc CLI";
      floai.enable = lib.mkEnableOption "FloSports flo CLI";
      handy.enable = lib.mkEnableOption "Handy push-to-talk speech-to-text";
      herdr.enable = lib.mkEnableOption "Herdr terminal workspace manager for AI coding agents";

      # Access
      work.enable = lib.mkEnableOption "FloSports work integrations (the executor-flo MCP gateway)";
      aikido.enable = lib.mkEnableOption "Aikido security-scan MCP server (local stdio)";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      description = "Jordan Garrison";
      extraGroups = [ "networkmanager" "wheel" "docker" "input" ];
      shell = pkgs.zsh;
      home = cfg.homeDirectory;
      # Merged with ~/.ssh/authorized_keys, which sshd still reads.
      openssh.authorizedKeys.keys = [
        # FloSports work machine
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDQbMQf/t5SLwjEaAyKnvX5BuARNIS17+Ax2d+4gZY91RR1NlHL6tqe5wIc9gZHHKcCUsxJvqYxdlvfaLUQokMy9t5oufRBN6Zdsu/81ndHvfcfhLFQ4pkJp2YdgWFmOCF9XA4GYWC4MO7cKrShzLp0F8sU6QyC7FKdU1AGPNb98s5MCtkIwQF/5mXs3A9HU2PRteBY5usQDfI/Gc4onSxfUZhoEO2J81UcVDiZdIIpmPMxNI4oQFQ60rblepmGvPERxeT+m+31FZZH/8Se8BXA2CQcaGu5uR3zDq3Gn6s1fOMcuU/0thi8JMf7jMA7M4THzc4CMiUDRO2Qo1D41VVF flosports"
        # opportunity
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHK/0jdVFwj1W0C+H03UHZySTCnsEi4usgj29afZgddG opportunity"
        # discovery (two keys)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILateDtawCsQ3tXgK34MjSwbLPCOOUc4/knJTKdDiIWa discovery"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtIJJJFQlRWAJ73n41j1JWGEfka9MSACO+3zM+QZqqT discovery-gh-cli"
        # voyager (garrisonsbygrace)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIESG8ITo2U4sVsFhXySY0WQcKpTAf5mBFUGC2hvU/Ob7 garrisonsbygrace@voyager"
        # heeler
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINZCTiF6GwFi57cDum1txkC4s3vi7CncdF+Oa9S97Lvh heeler"
        # Nodeterm on iOS
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFvbLhccCptdg0LDslDaU1s9Vp3M6XFCYsg2VKfXkqh9 nodeterm-ios"
        # Older key from a `jordan` account
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFz5m1fuEkavxH6zmjkoOaskDS+jubEZuj4UiNy17Fvk jordan"
        # grokbot box
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFgMo/VHZVPuLqmgXhCXK1E4naTDCXup7pa9YEUlzd9x box@grokbot-box"
      ];
      packages = with pkgs; [
        xournalpp
      ] ++ lib.optionals cfg.apps.calibre.enable [
        stable.calibre
      ] ++ lib.optionals cfg.apps.deskflow.enable [
        deskflow
      ] ++ lib.optionals cfg.apps.nextcloud.enable [
        stable.nextcloud-client
      ] ++ lib.optionals cfg.apps.obsidian.enable [
        obsidian
      ] ++ lib.optionals cfg.apps.todoist.enable [
        todoist-electron
      ] ++ lib.optionals cfg.apps.session-desktop.enable [
        # session-desktop: clear executable stack flag on better-sqlite3
        # glibc 2.41+ rejects dlopen of shared libraries with RWE GNU_STACK
        # https://github.com/NixOS/nixpkgs/issues/487524
        (session-desktop.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            for f in $(find $out -name "*.node" -type f); do
              if ${prelink}/bin/execstack -q "$f" 2>/dev/null | grep -q '^X'; then
                ${prelink}/bin/execstack -c "$f"
              fi
            done
          '';
        }))
      ] ++ lib.optionals cfg.apps.zoom.enable [
        zoom-us
      ];
    };

    # 1Password policy ownership for Jordan
    programs._1password-gui.polkitPolicyOwners = [ cfg.username ];

    # Enable passwordless sudo for Jordan
    security.sudo.extraRules = [{
      users = [ cfg.username ];
      commands = [{
        command = "ALL";
        options = [ "NOPASSWD" ];
      }];
    }];

    # Home Manager configuration for Jordan
    home-manager.users.${cfg.username} = if pkgs.stdenv.hostPlatform.isLinux then
      import ./home-linux.nix
    else
      import ./home-darwin.nix;
    home-manager.extraSpecialArgs = {
      inherit inputs;
      username = cfg.username;
      homeDirectory = cfg.homeDirectory;
      swapSuperAlt = cfg.swapSuperAlt;
      userApps = cfg.apps;
    };
  };
}
