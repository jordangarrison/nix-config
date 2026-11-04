{ config, pkgs, lib, username, homeDirectory, inputs, userApps ? {}, ... }:
{
  imports = [
    ./home.nix
    ../../modules/home/ghostty
  ];

  home.packages = lib.optionals (userApps.hermes-desktop.enable or false) [
    pkgs.llm-agents.hermes-desktop
  ];

  # Copy app bundles into ~/Applications/Home Manager Apps instead of
  # linking them. Spotlight and Launchpad do not index linked bundles.
  targets.darwin.linkApps.enable = false;
  targets.darwin.copyApps.enable = true;
}
