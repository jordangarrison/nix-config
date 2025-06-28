{ config, lib, pkgs, ... }:

{
  # Traditional PulseAudio setup
  services.pulseaudio = {
    enable = true;
    package = pkgs.pulseaudioFull;
  };

  # Disable PipeWire on hosts that keep PulseAudio
  services.pipewire.enable = lib.mkForce false;

  # Utilities / UCM profiles
  environment.systemPackages = with pkgs; [
    pavucontrol
    alsa-ucm-conf # UCM profiles for MacBook and other laptops
  ];
}

