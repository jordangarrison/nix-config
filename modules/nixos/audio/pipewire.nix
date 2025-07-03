{ config, lib, pkgs, ... }:

{
  # PipeWire replaces PulseAudio/JACK and provides compatibility layers
  services.pipewire = {
    enable = true;

    # Provide ALSA + PulseAudio compatibility
    alsa.enable  = true;
    pulse.enable = true;
    jack.enable  = false;

    # Use WirePlumber session manager (better policy handling)
    wireplumber.enable = true;
  };

  # Disable legacy PulseAudio service to avoid conflicts
  hardware.pulseaudio.enable = lib.mkForce false;

  # Helpful tools / profiles for troubleshooting
  environment.systemPackages = with pkgs; [
    pipewire
    wireplumber
    pavucontrol
    alsa-ucm-conf  # extra UCM profiles (Apple laptops, etc.)
  ];
}

