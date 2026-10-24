{ config, pkgs, lib, username, homeDirectory, inputs, userApps ? {}, ... }:
{
  imports = [
    ./home.nix
    ../../modules/home/ghostty
  ];

  home.packages = lib.optionals (userApps.hermes-desktop.enable or false) [
    pkgs.llm-agents.hermes-desktop
  ];
}
