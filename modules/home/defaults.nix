{ config, pkgs, ... }:

{
  # Common home-manager integration defaults for all hosts (NixOS and Darwin)
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
  };
}
