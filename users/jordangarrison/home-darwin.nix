{ config, pkgs, lib, username, homeDirectory, inputs, userApps ? {}, ... }:
{
  imports = [
    ./home.nix
    ../../modules/home/ghostty
    ../../modules/home/omniwm
  ];

  home.packages = [
    # Keep the upstream signature for Microphone and Accessibility grants.
    # copyApps below installs the bundle; see packages/hex-bin/README.md.
    (pkgs.callPackage ../../packages/hex-bin { })
  ] ++ lib.optionals (userApps.grok-bot.enable or false) [
    # Keep the upstream signature and notarization ticket for macOS grants.
    inputs.grok-bot.packages.${pkgs.stdenv.hostPlatform.system}.default
  ] ++ lib.optionals (userApps.hermes-desktop.enable or false) [
    pkgs.llm-agents.hermes-desktop
  ];

  # Copy app bundles into ~/Applications/Home Manager Apps instead of
  # linking them. Spotlight and Launchpad do not index linked bundles.
  targets.darwin.linkApps.enable = false;
  targets.darwin.copyApps.enable = true;
}
