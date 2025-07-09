{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.users.jane;
in
{
  options.users.jane = {
    enable = lib.mkEnableOption "Jane Garrison user account";

    username = lib.mkOption {
      type = lib.types.str;
      default = "jane";
      description = "Username for Jane's account";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.username}";
      description = "Home directory path for Jane";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.username} = {
      isNormalUser = true;
      description = "Jane Garrison";
      extraGroups = [ "networkmanager" ];
      shell = pkgs.bash;
      home = cfg.homeDirectory;
      packages = with pkgs; [
        # Jane's specific packages
      ];
    };

    # Basic Home Manager configuration for Jane
    home-manager.users.${cfg.username} = { pkgs, ... }: {
      home.stateVersion = "24.11";
      home.packages = with pkgs; [
        # Jane's home packages
      ];
      programs.home-manager.enable = true;
    };
  };
}
