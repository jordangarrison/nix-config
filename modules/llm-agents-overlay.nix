{ inputs, config, pkgs, ... }:

{
  # Overlay to make llm-agents packages available via pkgs.llm-agents.*
  # Provides: pkgs.llm-agents.claude-code, pkgs.llm-agents.codex, and more
  #
  # Upstream dropped its `overlays.default` output, so expose the input's
  # per-system `packages` set directly.
  nixpkgs.overlays = [
    (final: prev: {
      llm-agents = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system} // {
        # llm-agents.nix has not published omp 18.2.9 yet (no open PR; main is
        # still 18.2.8). That release is what adds claude-opus-5-5. Consume
        # oh-my-pi's own package until the updater lands, then drop this.
        omp = inputs.oh-my-pi.packages.${prev.stdenv.hostPlatform.system}.omp;
        # Locked llm-agents is still claude-code 2.1.278. Consume the latest
        # release from sadjow/claude-code-nix until flake-update picks up an
        # llm-agents rev that includes it, then drop this.
        claude-code = inputs.claude-code-nix.packages.${prev.stdenv.hostPlatform.system}.claude-code;
      };
    })
  ];
}
