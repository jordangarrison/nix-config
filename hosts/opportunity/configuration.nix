# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Workaround for kernel 7.1.0 HID battery regression (fixed upstream in
  # 7.1.1, commit b15b03d6): if the PIXA3854 touchpad / ILIT2901 touchscreen
  # first bind to hid-generic and are later re-probed by hid_multitouch, the
  # kernel oopses in hidinput_setup_battery. Loading hid_multitouch from the
  # initrd ensures it is registered before the I2C-HID devices appear, so no
  # re-probe happens. Safe to drop once confirmed running kernel >= 7.1.1.
  boot.initrd.kernelModules = [ "hid_multitouch" ];

  # Swap configuration
  swapDevices = [{
    device = "/swapfile";
    size = 48 * 1024;
  } # 48 GiB to match RAM
    ];

  networking.hostName = "opportunity"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Per-device keyboard remapping via keyd.
  # Listed devices get: caps -> esc/ctrl, and left/right Alt <-> Meta swap.
  # Any keyboard NOT listed here (e.g. QMK boards that handle their own
  # remapping) is left completely untouched — keyd does not open it.
  # Iterate live with `sudo keyd reload`; only the config file changes
  # need a rebuild to materialize into /etc/keyd/.
  services.keyd = {
    enable = true;
    keyboards.framework-and-k400 = {
      ids = [
        "0001:0001" # AT Translated Set 2 keyboard (Framework internal, PS/2)
        "046d:404b" # Logitech K400 wireless keyboard
      ];
      settings.main = {
        capslock = "overload(control, esc)";
        leftalt = "leftmeta";
        leftmeta = "leftalt";
        rightalt = "rightmeta";
        rightmeta = "rightalt";
      };
    };
  };

  # Opportuity-specific firewall configuration
  # GSConnect (KDE Connect for GNOME) firewall rules
  networking.firewall = rec {
    allowedTCPPortRanges = [{
      from = 1714;
      to = 1764;
    }];
    allowedUDPPortRanges = allowedTCPPortRanges;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
