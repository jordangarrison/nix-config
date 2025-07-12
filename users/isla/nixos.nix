{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.users.isla;
in
{
  options.users.isla = {
    enable = lib.mkEnableOption "Isla Garrison user account";

    username = lib.mkOption {
      type = lib.types.str;
      default = "isla";
      description = "Username for Isla's account";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.username}";
      description = "Home directory path for Isla";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      description = "Isla Garrison";
      extraGroups = [ "networkmanager" ];
      shell = pkgs.bash;
      home = cfg.homeDirectory;
      packages = with pkgs; [
        # Isla's specific packages
      ];
    };

    # Basic Home Manager configuration for Isla
    home-manager.users.${cfg.username} = { pkgs, ... }: {
      home.stateVersion = "24.11";
      home.packages = with pkgs; [
        # Isla's home packages
      ];
      programs.home-manager.enable = true;
    };
    home-manager.extraSpecialArgs = {
      inherit inputs;
      username = cfg.username;
      homeDirectory = cfg.homeDirectory;
    };
  };
}
