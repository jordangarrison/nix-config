# The Herdr desktop app package for this platform. Linux takes llm-agents.
# macOS takes the signed release bundle, starting at the llm-agents version,
# because the llm-agents build has no Herdr.app; see packages/herdr-app-bin.
{ pkgs }:
if pkgs.stdenv.hostPlatform.isDarwin then
  pkgs.callPackage ../../../packages/herdr-app-bin {
    inherit (pkgs.llm-agents.herdr-app) version;
  }
else
  pkgs.llm-agents.herdr-app
