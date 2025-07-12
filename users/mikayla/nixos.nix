{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.users.mikayla;
in
{
  options.users.mikayla = {
    enable = lib.mkEnableOption "Mikayla Garrison user account";

    username = lib.mkOption {
      type = lib.types.str;
      default = "mikayla";
      description = "Username for Mikayla's account";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.username}";
      description = "Home directory path for Mikayla";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      description = "Mikayla Garrison";
      extraGroups = [ "networkmanager" "wheel" ];
      shell = pkgs.bash;
      home = cfg.homeDirectory;
      packages = with pkgs; [
        # Mikayla's specific packages
      ];
    };

    # Basic Home Manager configuration for Mikayla
    home-manager.users.${cfg.username} = { pkgs, ... }: {
      home.stateVersion = "24.11";
      home.packages = with pkgs; [
        # Mikayla's home packages
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
