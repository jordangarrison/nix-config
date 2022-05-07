{ config, pkgs, lib, ... }:

let
  user = "@ENVSUB_USER@";
  password = "@ENVSUB_PASSWORD@";
  SSID = "@ENVSUB_SSID@";
  SSIDpassword = "@ENVSUB_SSID_PASSWORD@";
  interface = "@ENVSUB_INTERFACE@";
  hostname = "@ENVSUB_HOSTNAME@";
  piVersion = "@ENVSUB_PI_VERSION@";
in
{
  imports = [ "${fetchTarball "https://github.com/NixOS/nixos-hardware/archive/936e4649098d6a5e0762058cb7687be1b2d90550.tar.gz" }/raspberry-pi/${piVersion}" ];

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };

  networking = {
    hostName = hostname;
    wireless = {
      enable = true;
      networks."${SSID}".psk = SSIDpassword;
      interfaces = [ interface ];
    };
  };

  environment.systemPackages = with pkgs; [ vim ];

  services.openssh.enable = true;

  users = {
    mutableUsers = false;
    users."${user}" = {
      isNormalUser = true;
      password = password;
      extraGroups = [ "wheel" ];
    };
  };

  # Enable GPU acceleration
  hardware.raspberry-pi."${piVersion}".fkms-3d.enable = true;

  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    desktopManager.xfce.enable = true;
  };

  hardware.pulseaudio.enable = true;
}
