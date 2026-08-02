# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "voyager"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Keyboard remapping via keyd: caps -> esc on tap, ctrl on hold.
  # Applied to all keyboards (wildcard `*`) to preserve the previous
  # caps2esc behavior. To scope to specific devices, replace the wildcard
  # with vendor:product IDs (find via `cat /proc/bus/input/devices`).
  services.keyd = {
    enable = true;
    keyboards.default = {
      ids = [ "*" ];
      settings.main = {
        capslock = "overload(control, esc)";
      };
    };
  };

  # User configuration now handled by user modules in flake.nix

  # Voyager-specific firewall configuration
  # GSConnect (KDE Connect for GNOME) firewall rules
  networking.firewall = rec {
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };

  # Shared family storage on the SD card (/data, see disko.nix).
  # tmpfiles re-asserts ownership/modes every boot, so the layout
  # self-heals after the card is reformatted or files are restored.
  users.groups.family.members = [ "jordangarrison" "mikayla" "jane" "isla" ];

  systemd.tmpfiles.rules = [
    "d /data 0755 root family -"
    "d /data/jordangarrison 0755 jordangarrison users -"
    "d /data/mikayla 0755 mikayla users -"
    "d /data/jane 0755 jane users -"
    "d /data/isla 0755 isla users -"
    # setgid + sticky: files inherit the family group; only owners delete.
    "d /data/shared 3775 root family -"
  ];

  # Power management commands to restart wpa_supplicant on power up
  powerManagement.powerUpCommands = ''
    ${pkgs.systemd}/bin/systemctl restart wpa_supplicant.service
  '';

  # voyager does not sleep. See gbg-config.machine.type = "desktop" in flake.nix:
  # despite being a MacBook, this machine is treated as a server because S3
  # permanently kills the SD card reader that backs the family /data share.
  #
  # The reader is a USB3 device (Apple 05ac:8406, hardwired on usb2-port3), not
  # a PCIe/mmc controller. Across S3 the SuperSpeed link never retrains: resume
  # logs "usb 2-3: USB disconnect" followed by "usb usb2-port3: Cannot enable.
  # Maybe the USB cable is bad?" retrying every ~4s forever, and /data is gone.
  # Only a cold power-off brings it back — a warm reboot is not enough.
  #
  # Measured on this hardware (6.18.40), all confirmed applied and all failed:
  #   usbcore.quirks=05ac:8406:m  USB_QUIRK_DISCONNECT_SUSPEND. Device reported
  #     quirks=0x1000; reader still did not re-enumerate.
  #   xhci_hcd.quirks=0x80        XHCI_RESET_ON_RESUME. Controller quirks went
  #     0x4b810 -> 0x4b890 and the reset did fire ("root hub lost power or was
  #     reset"); USB2 devices recovered, port3 did not.
  #   Full xhci_hcd PCI unbind/rebind. Controller re-probed from scratch,
  #     keyboard/trackpad/bluetooth returned, port3 still dead.
  # USB_QUIRK_DISABLE_LINK_ON_SUSPEND was proposed upstream for exactly this
  # device in 2019 but never merged, so there is no quirk letter for it.
  #
  # Hence: no suspend at all. Lid close locks instead.
  services.logind.settings.Login = {
    HandleLidSwitch = "lock";
    HandleLidSwitchExternalPower = "lock";
    HandleLidSwitchDocked = "ignore";
  };

  # Belt and braces: sleep should be unreachable via machine.type = "desktop",
  # but if anything ever does put this machine to sleep, unmount /data cleanly
  # first so ext4 is not torn down mid-write ("device offline error ...
  # Aborting journal"), which is how the original data loss happened.
  #
  # A dedicated unit rather than powerManagement.{powerDown,resume}Commands on
  # purpose: those merge into one script that runs under `set -e`, and
  # nixos-hardware's apple profile contributes a bare `rmmod brcmfmac` that wins
  # the ordering tie even against mkBefore — so when that module isn't loaded the
  # script aborts and the flush is silently skipped. ExecStart runs before sleep
  # and ExecStop after wake, the same mechanism NixOS's own sleep-actions uses.
  systemd.services.sdcard-sleep = {
    description = "Unmount /data (SD card) across suspend";
    before = [ "sleep.target" ];
    wantedBy = [ "sleep.target" ];
    unitConfig.StopWhenUnneeded = true;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "sdcard-suspend" ''
        ${pkgs.coreutils}/bin/sync
        ${pkgs.systemd}/bin/systemctl stop data.mount \
          || ${pkgs.util-linux}/bin/umount -l /data \
          || true
      '';
      # Re-enumeration takes a second or two after wake, so wait for the udev
      # symlink rather than racing it. Only then attempt the mount: `systemctl
      # start data.mount` blocks indefinitely on a .device unit that will never
      # appear, so calling it unconditionally hangs the stop job until the
      # timeout. Exit non-zero instead, so a reader that stayed dead is visible
      # in `systemctl status` rather than silently hidden.
      ExecStop = pkgs.writeShellScript "sdcard-resume" ''
        i=0
        while [ ! -e /dev/disk/by-partlabel/disk-sdcard-data ] && [ $i -lt 30 ]; do
          ${pkgs.coreutils}/bin/sleep 1
          i=$((i + 1))
        done
        if [ ! -e /dev/disk/by-partlabel/disk-sdcard-data ]; then
          echo "SD reader did not re-enumerate after resume; leaving /data unmounted" >&2
          exit 1
        fi
        ${pkgs.systemd}/bin/systemctl start data.mount
      '';
      TimeoutStopSec = 60;
    };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?

}
