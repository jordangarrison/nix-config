{
  buildNpmPackage,
  lib,
}:

buildNpmPackage {
  pname = "jordangarrison-pi-extensions";
  version = "1.2.0";

  src = ./.;
  # Refresh with `npm install --package-lock-only --ignore-scripts --legacy-peer-deps`,
  # then recompute using `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-X0VIA9KoWMQI9Zve8c5ZyOsfG2TkEhZJQlZpiIU9j3w=";

  dontNpmBuild = true;
  dontNpmPrune = true;
  npmInstallFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  npmPackFlags = [ "--ignore-scripts" ];

  postInstall = ''
    # The upstream compact status shows remaining quota without saying so.
    # Display the complement explicitly so the footer answers "how much used?".
    substituteInPlace \
      "$out/lib/node_modules/jordangarrison-pi-extensions/node_modules/@narumitw/pi-usage/src/format.ts" \
      --replace-fail \
        'clampPercent(bucket.remaining).toFixed(0)}% ' \
        '(100 - clampPercent(bucket.remaining)).toFixed(0)}% used '

    # Claude Bridge always uses the separately Nix-managed Claude Code binary,
    # so omit the Agent SDK's redundant 220+ MiB platform binary from the result.
    rm -rf "$out/lib/node_modules/jordangarrison-pi-extensions/node_modules/@anthropic-ai"/claude-agent-sdk-{darwin,linux,win32}-*
  '';

  meta = {
    description = "Reproducible bundle of Pi extensions managed by Nix";
    license = lib.licenses.mit;
  };
}
