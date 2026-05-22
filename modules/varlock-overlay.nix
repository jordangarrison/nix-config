{ ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      varlock = final.callPackage ../packages/varlock { };
    })
  ];
}
