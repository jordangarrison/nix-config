{ inputs, config, pkgs, ... }:

{
  # Overlay to make Zed extensions available via pkgs.zed-extensions.*
  nixpkgs.overlays = [ inputs.nix-zed-extensions.overlays.default ];
}
