{ ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      readwise-cli = final.callPackage ../packages/readwise-cli { };
    })
  ];
}
