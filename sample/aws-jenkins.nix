{ config, pkgs, ... }:

{
  imports = [ <nixpkgs/nixos/modules/virtualisation/amazon-image.nix> ];
  ec2.hvm = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.nix-user = {
    isNormalUser = true;
    initialHashedPassword = "";
    extraGroups = [
      "wheel" # Enable ‘sudo’ for the user.
      "docker"
    ];
  };


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
    # utilities - we don't actually need these we could just nix-shell -p them
    vim
    wget
    htop
    git
    gh
    dig
    jq
    ripgrep
    tmux
    fd
  ];

  # List services that you want to enable:

  # Docker
  virtualisation.docker.enable = true;
  virtualisation.libvirtd.enable = true;

  # NFS
  # fileSystems = {
  #   "/mnt/data" = {
  #     device = "efshost:/export/garrisonsbygrace";
  #     fsType = "nfs";
  #     options = [ "x-systemd.automount" ];
  #   };
  # };

  # Testing out Jenkins
  services.jenkins = {
    enable = true;
    port = 80;
  };

}
