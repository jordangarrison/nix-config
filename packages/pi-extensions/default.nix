{
  buildNpmPackage,
  lib,
}:

buildNpmPackage {
  pname = "jordangarrison-pi-extensions";
  version = "1.1.0";

  src = ./.;
  # Refresh with `npm install --package-lock-only --ignore-scripts --legacy-peer-deps`,
  # then recompute using `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-g+3RHyZzbudytpsajypdF06Auq4pbVOGllJYNLJn0ho=";

  dontNpmBuild = true;
  dontNpmPrune = true;
  npmInstallFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  npmPackFlags = [ "--ignore-scripts" ];

  # Claude Bridge always uses the separately Nix-managed Claude Code binary,
  # so omit the Agent SDK's redundant 220+ MiB platform binary from the result.
  postInstall = ''
    rm -rf "$out/lib/node_modules/jordangarrison-pi-extensions/node_modules/@anthropic-ai"/claude-agent-sdk-{darwin,linux,win32}-*
  '';

  meta = {
    description = "Reproducible bundle of Pi extensions managed by Nix";
    license = lib.licenses.mit;
  };
}
