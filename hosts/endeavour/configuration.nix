# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running 'nixos-help').

{ config, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Intel WiFi AX200 stability improvements
  # Disables problematic WiFi 6 features and power saving that cause disconnections
  boot.extraModprobeConfig = ''
    options iwlwifi 11n_disable=8 power_save=0 swcrypto=1
  '';

  networking.hostName = "endeavour"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # NetworkManager WiFi stability settings
  networking.networkmanager.wifi = {
    # Disable power saving on WiFi interfaces
    powersave = false;
    # Prefer 5GHz networks when available
    scanRandMacAddress = false;
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Endeavour-specific display manager settings
  services.displayManager.autoLogin.enable = false;

  # Enable remote desktop services
  services.xrdp = {
    enable = false;
    defaultWindowManager = "gnome-session";
  };

  systemd.services."gnome-remote-desktop".wantedBy = [ "graphical.target" ];
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Enable Logitech Unifying Receiver (endeavour-specific hardware)
  hardware.logitech.wireless.enable = true;
  hardware.logitech.wireless.enableGraphical = true;

  # User configuration now handled by user modules in flake.nix

  # Endeavour-specific system packages
  environment.systemPackages = with pkgs;
    [
      # Para Gnome
      shotwell

      # Windows virtualized
      winboat
    ];

  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
