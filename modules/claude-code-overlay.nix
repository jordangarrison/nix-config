{ inputs, config, pkgs, ... }:

{
  # Overlay to make claude-code available via pkgs.claude-code
  # Also provides pkgs.claude-code-node and pkgs.claude-code-bun variants
  nixpkgs.overlays = [ inputs.claude-code.overlays.default ];
}
