{ config, lib, pkgs, osConfig ? null, ... }:

let
  # Show OSK script - starts wvkbd if not running
  showOsk = pkgs.writeShellScript "show-osk" ''
    if ! ${pkgs.procps}/bin/pgrep -x wvkbd-mobintl > /dev/null; then
      ${pkgs.wvkbd}/bin/wvkbd-mobintl &
    fi
  '';

  # Hide OSK script - kills wvkbd to hide it completely
  hideOsk = pkgs.writeShellScript "hide-osk" ''
    ${pkgs.procps}/bin/pkill wvkbd-mobintl
  '';

  # Gesture definitions for lisgd
  # Format: -g nfingers,gesture,edge,distance,actmode,command
  # Gestures:
  #   LR = left-to-right, RL = right-to-left
  #   DU = down-to-up, UD = up-to-down
  # Edge: * = any, N = none, L/R/T/B = left/right/top/bottom
  # Distance: * = any, S = short, M = medium, L = large
  # Actmode: R = release, P = pressed
  gestures = [
    # 3-finger swipe left/right: workspace navigation
    "-g '3,LR,*,*,R,niri msg action focus-workspace-down'"
    "-g '3,RL,*,*,R,niri msg action focus-workspace-up'"

    # 3-finger swipe up from bottom: toggle launcher
    "-g '3,DU,B,*,R,noctalia-shell ipc call launcher toggle'"

    # 3-finger swipe down from top: close window
    "-g '3,UD,T,*,R,niri msg action close-window'"

    # 1-finger swipe up from bottom edge (short distance): show OSK
    "-g '1,DU,B,S,R,${showOsk}'"

    # 2-finger swipe down from top: hide OSK (easier to dismiss when keyboard visible)
    "-g '2,UD,T,*,R,${hideOsk}'"

    # 2-finger swipe left/right: browser back/forward navigation
    "-g '2,LR,*,*,R,${pkgs.wtype}/bin/wtype -M alt -k Right -m alt'"
    "-g '2,RL,*,*,R,${pkgs.wtype}/bin/wtype -M alt -k Left -m alt'"
  ];
in {
  # Packages for tablet mode
  home.packages = with pkgs; [
    lisgd    # Touchscreen gesture daemon
    iio-niri # Auto-rotation for niri
    wvkbd    # On-screen keyboard
    wtype    # Wayland key simulation for gestures
  ];

  # lisgd systemd service for touchscreen gestures
  systemd.user.services.lisgd = {
    Unit = {
      Description = "Touchscreen gesture daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.lisgd}/bin/lisgd -d /dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event ${lib.concatStringsSep " " gestures}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # iio-niri systemd service for auto-rotation
  systemd.user.services.iio-niri = {
    Unit = {
      Description = "Auto-rotation for niri";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.iio-niri}/bin/iio-niri";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
