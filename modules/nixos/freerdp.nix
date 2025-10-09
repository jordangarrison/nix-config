{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.freerdp;
in
{
  options.services.freerdp = {
    enable = mkEnableOption "FreeRDP remote desktop client and tools";

    enableServer = mkOption {
      type = types.bool;
      default = false;
      description = "Enable FreeRDP server components (experimental)";
    };
  };

  config = mkIf cfg.enable {
    # Install FreeRDP client packages
    environment.systemPackages = with pkgs; [
      freerdp      # FreeRDP 2.x
      freerdp3     # FreeRDP 3.x
    ];

    # Optional: Server configuration (if enableServer is true)
    # Note: FreeRDP server support is experimental and may require additional configuration
  };
}
