{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.tablet-mode;
in {
  options.tablet-mode = {
    enable = mkEnableOption "tablet mode support (touch gestures, auto-rotation, OSK)";
  };

  config = mkIf cfg.enable {
    # Enable iio-sensor-proxy for accelerometer (required for auto-rotation)
    hardware.sensor.iio.enable = true;
  };
}
