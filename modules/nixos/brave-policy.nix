{ ... }:

{
  # Companion to modules/brave-overlay.nix. Keep this NixOS-only: standalone
  # Home Manager has no environment.etc option.
  environment.etc."brave/policies/managed/disable-bad-flag-warnings.json".text = builtins.toJSON {
    CommandLineFlagSecurityWarningsEnabled = false;
  };
}
