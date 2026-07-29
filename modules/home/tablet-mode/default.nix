{ config, lib, pkgs, osConfig ? null, ... }:

let
  # Touchscreen (ILIT2901 via I2C-HID). This by-path symlink only exists once
  # the touchscreen has probed successfully, which can be after
  # graphical-session.target — so lisgd must wait for it instead of assuming
  # it is present at service start.
  touchscreenDevice =
    "/dev/input/by-path/pci-0000:00:15.0-platform-i2c_designware.0-event";

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

  # Wait for the touchscreen device before starting lisgd; libinput treats a
  # missing path as a client bug and lisgd exits immediately, so without the
  # wait the service fails in a restart loop whenever the touchscreen probes
  # late (or not at all).
  lisgdStart = pkgs.writeShellScript "lisgd-start" ''
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      [ -e ${touchscreenDevice} ] && break
      ${pkgs.coreutils}/bin/sleep 1
    done
    if [ ! -e ${touchscreenDevice} ]; then
      echo "lisgd: touchscreen device ${touchscreenDevice} did not appear within 60s" >&2
      exit 1
    fi
    exec ${pkgs.lisgd}/bin/lisgd -d ${touchscreenDevice} ${
      lib.concatStringsSep " " gestures
    }
  '';
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
      ExecStart = "${lisgdStart}";
      Restart = "on-failure";
      RestartSec = 10;
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
      ExecStart = "${pkgs.iio-niri}/bin/iio-niri listen";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
