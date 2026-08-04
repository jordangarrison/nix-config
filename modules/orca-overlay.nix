{ ... }:

{
  # Overlay to make orca-ide available. Named orca-ide (upstream's deb/binary
  # name) rather than orca to avoid clobbering the GNOME screen reader.
  nixpkgs.overlays = [
    (final: prev: {
      orca-ide = final.callPackage ../packages/orca-ide { };
    })
  ];
}
