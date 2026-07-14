{ inputs, config, pkgs, ... }:

{
  # Overlay to make llm-agents packages available via pkgs.llm-agents.*
  # Provides: pkgs.llm-agents.claude-code, pkgs.llm-agents.codex, and more
  #
  # Upstream dropped its `overlays.default` output, so expose the input's
  # per-system `packages` set directly (same source the herdr-pin input uses).
  nixpkgs.overlays = [
    (final: prev: {
      llm-agents = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system};
    })
  ];
}
