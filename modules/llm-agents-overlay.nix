{ inputs, config, pkgs, ... }:

{
  # Overlay to make llm-agents packages available via pkgs.llm-agents.*
  # Provides: pkgs.llm-agents.claude-code, pkgs.llm-agents.codex, and more
  nixpkgs.overlays = [ inputs.llm-agents.overlays.default ];
}
