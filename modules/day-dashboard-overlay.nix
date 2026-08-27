{ ... }:

{
  # Overlay to make pkgs.day-dashboard available. It needs the Pi CLI, which
  # this repo exposes as pkgs.llm-agents.pi (see llm-agents-overlay.nix), so
  # thread that in explicitly rather than relying on a top-level pkgs.pi. `gws`
  # (Google Workspace CLI, for the email/calendar collectors) resolves from the
  # normal package set.
  nixpkgs.overlays = [
    (final: prev: {
      day-dashboard = final.callPackage ../packages/day-dashboard {
        pi = final.llm-agents.pi;
      };
    })
  ];
}
