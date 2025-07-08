# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

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

  networking.hostName = "endeavour"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.autoSuspend = false;
  services.displayManager.autoLogin.enable = false;
  services.desktopManager.gnome.enable = true;
  services.gnome.gnome-remote-desktop.enable = true;

  services.xrdp = {
    enable = true;
    defaultWindowManager = "gnome-session";
  };

  services.dbus.enable = true;

  systemd.services."gnome-remote-desktop".wantedBy = [ "graphical.target" ];
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable Logitech Unifying Receiver
  hardware.logitech.wireless.enable = true;
  hardware.logitech.wireless.enableGraphical = true;

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.jordangarrison = {
    isNormalUser = true;
    description = "Jordan Garrison";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.zsh;
    packages = with pkgs; [
      deskflow
      obsidian
      thunderbird
      todoist-electron
    ];
  };

  # Install firefox.
  programs.firefox.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "jordangarrison" ];
  };
  programs._1password.enable = true;

  programs.zsh.enable = true;

  # Enable AppImage support
  programs.appimage = {
    enable = true;
    binfmt = true; # Registers ELF AppImages for direct execution
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    curl
    brave

    # Gnome
    gnome-remote-desktop
    gnome-session
    gnome-tweaks
    gnomeExtensions.clipboard-history

    # Para Gnome
    shotwell
  ];

  services.gnome.core-shell.enable = true;
  programs.dconf.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable flatpaks
  services.flatpak.enable = true;

  # Enable Docker
  virtualisation.docker.enable = true;

  # Enable Tailscale
  services.tailscale.enable = true;

  # Open ports in the firewall.
  # networking.firewall = rec {
  #   allowedTCPPortRanges = [{ from = 1714; to = 1764; } 24800];
  #   allowedUDPPortRanges = allowedTCPPortRanges;
  # };
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
