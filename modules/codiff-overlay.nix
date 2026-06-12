{ ... }:

{
  # Overlay to make codiff available
  nixpkgs.overlays = [
    (final: prev: {
      codiff = final.callPackage ../packages/codiff { };
    })
  ];
}
