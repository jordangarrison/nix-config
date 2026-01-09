{ config, pkgs, ... }:

{
  # Enable nix flakes and new command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  # Enable networking
  networking.networkmanager.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable zsh system-wide
  programs.zsh.enable = true;

  # Enable AppImage support
  programs.appimage = {
    enable = true;
    binfmt = true; # Registers ELF AppImages for direct execution
  };

  # Enable dconf for GNOME settings
  programs.dconf.enable = true;

  # Localsend for transferring files
  programs.localsend.enable = true;

  # KDE Connect for device connectivity (works with GSConnect on GNOME)
  programs.kdeconnect.enable = true;

  # Common system packages that should be available everywhere
  environment.systemPackages = with pkgs; [ vim wget curl brave ];

  # Enable OpenSSH daemon
  services.openssh.enable = true;

  # Enable Tailscale (critical networking infrastructure)
  services.tailscale.enable = true;

  # Enable flatpak support
  services.flatpak.enable = true;

  # Enable CUPS to print documents
  services.printing.enable = true;

  # Enable rtkit for real-time audio scheduling
  security.rtkit.enable = true;
}
