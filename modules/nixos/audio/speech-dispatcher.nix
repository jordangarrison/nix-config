{ ... }:

{
  # Provides the TTS backend Chromium/Brave/Firefox use for the Web Speech
  # API on Linux. Without it, speechSynthesis.getVoices() returns [] and
  # utterances fire synthesis-failed. espeak-ng is pulled in as the default
  # output module.
  #
  # On its own this just enables a per-user, local Unix-socket daemon — low
  # risk. The notable security implications come from how Brave is wired to
  # consume it; see modules/brave-overlay.nix for the full caveats.
  services.speechd.enable = true;
}
