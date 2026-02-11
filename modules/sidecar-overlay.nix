{ inputs, config, pkgs, ... }:

{
  # Overlay to make sidecar and td available
  nixpkgs.overlays = [
    (final: prev: {
      sidecar = final.callPackage ../packages/sidecar { };
      td = final.callPackage ../packages/td { };
    })
  ];
}
