{ config, pkgs, lib, username, homeDirectory, inputs, ... }:
{
  imports = [
    ./home.nix
  ];
}
