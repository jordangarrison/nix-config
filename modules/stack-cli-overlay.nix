{ ... }:

{
  # Overlay to make stack (kitlangton/stack, stacked-PR CLI) available.
  # Attribute is stack-cli to avoid shadowing pkgs.stack (Haskell tool);
  # the installed command is still `stack`.
  nixpkgs.overlays = [
    (final: prev: {
      stack-cli = final.callPackage ../packages/stack-cli { };
    })
  ];
}
