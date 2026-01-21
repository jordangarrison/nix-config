{ inputs, config, pkgs, ... }:

{
  # Overlay to make ralph available via pkgs.ralph
  nixpkgs.overlays = [
    (final: prev: {
      ralph = final.callPackage ../packages/ralph { };
    })
  ];
}
