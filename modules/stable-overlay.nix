{ inputs, config, pkgs, ... }:

{
  # Overlay to make stable packages available via pkgs.stable.*
  nixpkgs.overlays = [
    (final: prev: {
      stable = import inputs.nixpkgs-stable {
        system = final.stdenv.hostPlatform.system;
        config.allowUnfree = true;
      };
    })
  ];
}
