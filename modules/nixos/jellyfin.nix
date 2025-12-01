{ config, lib, pkgs, ... }:

{
  # Enable Jellyfin media server
  services.jellyfin = {
    enable = true;
    openFirewall = true;
  };

  # Add jellyfin user to video and render groups for GPU access
  users.users.jellyfin.extraGroups = [ "video" "render" ];

  # Install Jellyfin packages and AMD GPU drivers for hardware acceleration
  environment.systemPackages = with pkgs; [
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
  ];

  # Enable AMD GPU drivers for VAAPI hardware transcoding
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd  # AMD OpenCL driver
      libva-vdpau-driver  # VAAPI to VDPAU driver
      libvdpau-va-gl      # VDPAU to VA-GL driver
    ];
  };
}
