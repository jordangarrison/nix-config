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

      # Dev tools (heavy, built from source)
      freelens.enable = lib.mkEnableOption "Freelens Kubernetes IDE";
      sidecar.enable = lib.mkEnableOption "Sidecar TUI for coding agents";
      codex.enable = lib.mkEnableOption "Codex and OpenCode LLM agents";
      grove.enable = lib.mkEnableOption "Grove workspace manager";
      google-cloud-sdk.enable = lib.mkEnableOption "Google Cloud SDK";
      azure-cli.enable = lib.mkEnableOption "Azure CLI";
      okta.enable = lib.mkEnableOption "Okta CLI client";
      handy.enable = lib.mkEnableOption "Handy push-to-talk speech-to-text";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      description = "Jordan Garrison";
      extraGroups = [ "networkmanager" "wheel" "docker" "input" ];
      shell = pkgs.zsh;
      home = cfg.homeDirectory;
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
        logseq
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
    home-manager.users.${cfg.username} = if pkgs.stdenv.isLinux then
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
