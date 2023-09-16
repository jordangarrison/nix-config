# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  unstableTarball = fetchTarball
    "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz";
in
{
  imports = [
    # Include the results of the hardware scan.
    # ./hardware-configuration.nix
    ./hardware-configuration-endeavour-vm.nix
    # ./hardware-configuration-endeavour-hw.nix
    # VSCode Server
    (fetchTarball
      "https://github.com/msteen/nixos-vscode-server/tarball/master")
  ];

  # Use the systemd-boot EFI boot loader.
  # If in a VM
  boot.loader.grub.device = "/dev/sda";

  # If physical device
  # boot.loader.systemd-boot.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "endeavour"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp42s0.useDHCP = true;
  networking.interfaces.wlo1.useDHCP = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  # };

  # environment.pathsToLink = [ "/libexec" ];

  # GUI
  services.xserver = {
    enable = true;
    displayManager = {
      gdm = {
        enable = true;
        # prevent autosuspend when no user is logged in
        autoSuspend = false;
      };
    };
    # Enable the GNOME Desktop Environment.
    desktopManager.gnome.enable = true;
  };
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gnome-remote-desktop.enable = true;

  # services.xserver.enable = true;
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.desktopManager.plasma5.enable = true;

  # services.xrdp.enable = true;
  # services.xrdp.defaultWindowManager = "startplasma-x11";
  # services.xrdp.openFirewall = true;

  # Env vars
  # environment.variables = {
  #   # Set sandbox variable for gnome accounts to work
  #   WEBKIT_FORCE_SANDBOX = "0";
  # };

  # Configure keymap in X11
  # services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Enable Code Server
  services.code-server = {
    enable = true;
    user = "jordangarrison";
    group = "users";
    extraArguments = [ "--disable-telemetry" ];
    host = "0.0.0.0";
    auth = "none";
  };

  services.avahi = {
    enable = true;
    nssmdns = true;
    wideArea = true;
    openFirewall = true;
    publish = {
      enable = true;
      workstation = true;
      addresses = true;
      userServices = true;
    };
  };

  services.qemuGuest.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.jordangarrison = {
    isNormalUser = true;
    initialHashedPassword = "";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "docker"
      "plugdev"
    ];
    shell = pkgs.zsh;
  };

  nix.settings.trusted-users = [ "root" "jordangarrison" ];

  hardware.keyboard.zsa.enable = true;

  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;
    packageOverrides = pkgs:
      with pkgs; {
        unstable = import unstableTarball { config = config.nixpkgs.config; };
      };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # utilities
    unstable.k9s
    btop
    vim
    wget
    htop
    git
    gh
    glibc
    diff-so-fancy
    zsh
    starship
    hstr
    dig
    # fnm
    bat
    jq
    ripgrep
    tmux
    fd

    # Servers
    # unstable.shairport-sync

    # Languages, runtimes and SDKs
    unstable.go
    unstable.nodejs
    python39Full
    nixpkgs-fmt
    # google-cloud-sdk

    # services
    tailscale

    #fonts
    fira-code

    # Desktop
    unstable._1password-gui
    unstable._1password
    unstable.brave
    unstable.todoist
    unstable.vscode
    alacritty
    firefox
    input-remapper
    nextcloud-client
    uxplay
    vlc
    xsel
    gparted
    gnome.gnome-tweaks
    gnome.gnome-remote-desktop
    gnome3.gnome-settings-daemon
    gnomeExtensions.appindicator
    gnomeExtensions.sound-output-device-chooser
    gnomeExtensions.clipboard-indicator
    gnomeExtensions.system-monitor

    (import (fetchTarball https://github.com/cachix/devenv/archive/v0.6.2.tar.gz)).default
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Steam
  # programs.steam = {
  #   enable = true;
  #   remotePlay.openFirewall = true;
  #   dedicatedServer.openFirewall = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable shairport-sync.
  # services.shairport-sync = {
  #   enable = true;
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
  networking.extraHosts = ''
    127.0.0.1 www.milesplit.local
  '';

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "21.11"; # Did you read the comment?

  # tailscale
  services.tailscale.enable = true;
  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";

    # make sure tailscale is running before trying to connect to tailscale
    after = [ "network-pre.target" "tailscale.service" ];
    wants = [ "network-pre.target" "tailscale.service" ];
    wantedBy = [ "multi-user.target" ];

    # set this service as a oneshot job
    serviceConfig.Type = "oneshot";

    # have the job run this shell script
    script = with pkgs; ''
      # wait for tailscaled to settle
      sleep 2

      # check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
      if [ $status = "Running" ]; then # if so, then do nothing
        exit 0
      fi

      # otherwise authenticate with tailscale
      ${tailscale}/bin/tailscale up -authkey @ENVSUB_TAILSCALE_AUTHKEY@
    '';
  };

  # Docker
  virtualisation.docker.enable = true;
  # Docker services
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      "jsoncrack" = {
        image = "shokohsc/jsoncrack";
        ports = [ "8888:8080" ];
      };
    };
  };

  # VSCode Server
  services.vscode-server.enable = true;

  # Flatpaks
  services.flatpak.enable = true;

  # NFS
  fileSystems = {
    "/mnt/garrisonsbygrace" = {
      device = "@ENVSUB_NFS_HOST@:/export/garrisonsbygrace";
      fsType = "nfs";
      options = [ "x-systemd.automount" ];
    };
  };

  # Workarounds

  # Network Manager breaks nixos rebuild switch
  # https://discourse.nixos.org/t/how-to-disable-networkmanager-wait-online-service-in-the-configuration-file/19963/4
  # https://github.com/NixOS/nixpkgs/issues/180175
  systemd.services.NetworkManager-wait-online.enable = false;
}

