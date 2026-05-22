{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs_22,
  makeWrapper,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "varlock";
  version = "1.2.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/varlock/-/varlock-${finalAttrs.version}.tgz";
    hash = "sha256-XAR5zYmQ/00T7DFZmbD8EzOyR12OsEe7mfKeDnZZV84=";
  };

  sourceRoot = "package";

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/varlock $out/bin
    cp -r bin dist package.json $out/lib/varlock/
    if [ -d native-bins ]; then
      cp -r native-bins $out/lib/varlock/
    fi

    makeWrapper ${nodejs_22}/bin/node $out/bin/varlock \
      --add-flags $out/lib/varlock/bin/cli.js

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/varlock --version | grep -F "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "AI-safe .env files: schemas for agents, secrets for humans";
    homepage = "https://varlock.dev";
    license = lib.licenses.mit;
    mainProgram = "varlock";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
})
