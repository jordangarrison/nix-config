{ ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      namespace-cli = final.callPackage ../packages/namespace-cli { };
    })
  ];
}
