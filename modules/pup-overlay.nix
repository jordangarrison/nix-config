{ ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      pup = final.callPackage ../packages/pup { };
    })
  ];
}
