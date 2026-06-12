{ ... }:

{
  # Overlay to make plannotator available
  nixpkgs.overlays = [
    (final: prev: {
      plannotator = final.callPackage ../packages/plannotator { };
    })
  ];
}
