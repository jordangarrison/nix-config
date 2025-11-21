{ inputs, config, pkgs, ... }:

{
  # Overlay to make stable packages available via pkgs.stable.*
  nixpkgs.overlays = [
    (final: prev: {
      master = import inputs.nixpkgs-master {
        system = final.system;
        config.allowUnfree = true;
      };
    })
  ];
}
