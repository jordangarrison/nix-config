{ inputs, config, pkgs, ... }:

{
  # Overlay to make stable packages available via pkgs.stable.*
  nixpkgs.overlays = [
    (final: prev: {
      master = import inputs.nixpkgs-master {
        localSystem.system = final.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
    })
  ];
}
