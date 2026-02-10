{ inputs, config, pkgs, ... }:

{
  # Overlay to make okta-cli-client available via pkgs.okta-cli-client
  nixpkgs.overlays = [
    (final: prev: {
      okta-cli-client = final.callPackage ../packages/okta-cli-client { };
    })
  ];
}
