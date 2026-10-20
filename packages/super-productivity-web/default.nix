# Static web build of Super Productivity (the same `dist/browser` the upstream
# Docker image serves from nginx). Reuses nixpkgs' super-productivity source and
# npm dependency cache, but runs the productionWeb frontend build instead of
# packaging the Electron app.
{ super-productivity }:

super-productivity.overrideAttrs (old: {
  pname = "super-productivity-web";

  desktopItems = [ ];

  buildPhase = ''
    runHook preBuild

    # Same plugin-package install as the nixpkgs Electron build.
    find packages -name package-lock.json | while read -r p; do
      npm --prefix "$(dirname $p)" ci --ignore-scripts
    done
    patchShebangs packages

    npm run prepare
    npm run buildFrontend:prodWeb

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist/browser $out
    runHook postInstall
  '';

  meta = builtins.removeAttrs old.meta [ "mainProgram" ] // {
    description = "Super Productivity web app (static build)";
  };
})
