{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.users.jordangarrison;
in
{
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
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      description = "Jordan Garrison";
      extraGroups = [ "networkmanager" "wheel" "docker" ];
      shell = pkgs.zsh;
      home = cfg.homeDirectory;
      packages = with pkgs; [
        deskflow
        obsidian
        thunderbird
        todoist-electron
      ];
    };

    # 1Password policy ownership for Jordan
    programs._1password-gui.polkitPolicyOwners = [ cfg.username ];

    # Home Manager configuration for Jordan
    home-manager.users.${cfg.username} = import ./home.nix;
    home-manager.extraSpecialArgs = {
      inherit inputs;
      username = cfg.username;
      homeDirectory = cfg.homeDirectory;
    };
  };
}
