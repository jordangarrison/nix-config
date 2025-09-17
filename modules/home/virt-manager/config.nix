{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.virtManager;
in
{
  options.virtManager = {
    enable = mkEnableOption "virt-manager configuration";

    autoConnect = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to automatically connect to QEMU/KVM hypervisor on startup";
    };

    connections = mkOption {
      type = types.listOf types.str;
      default = [ "qemu:///system" ];
      description = "List of hypervisor connections to configure";
    };

    autostart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable autostart for the default network";
    };

    workspaceAssignment = mkOption {
      type = types.nullOr types.int;
      default = 8;
      description = "GNOME workspace to assign virt-manager to (null to disable auto-assignment)";
    };
  };

  config = mkIf cfg.enable {
    # Configure virt-manager through dconf
    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = mkIf cfg.autoConnect {
        autoconnect = cfg.connections;
        uris = cfg.connections;
      };
      
      # Additional virt-manager preferences
      "org/virt-manager/virt-manager" = {
        # Remember window size and position
        manager-window-height = mkDefault 550;
        manager-window-width = mkDefault 800;
        
        # Default to showing all connections
        show-domain-creator = mkDefault true;
        
        # Enable system tray icon
        system-tray = mkDefault true;
      };

      # Configure the console settings for better VM interaction
      "org/virt-manager/virt-manager/console" = {
        # Enable resize guest with window
        resize-guest = mkDefault 1;
        
        # Grab keys combination
        grab-keys = mkDefault "ctrl_alt";
        
        # Scaling mode
        scaling = mkDefault 1;  # Always scale to fit window
      };
    };

    # Add virt-manager to GNOME auto-move-windows extension if workspace is specified
    dconf.settings."org/gnome/shell/extensions/auto-move-windows" = mkIf (cfg.workspaceAssignment != null) {
      application-list = mkDefault [ "virt-manager.desktop:${toString cfg.workspaceAssignment}" ];
    };
  };
}
