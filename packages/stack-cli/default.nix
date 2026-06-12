{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs,
}:

stdenvNoCC.mkDerivation rec {
  pname = "stack-cli";
  version = "0.2.0";

  # npm tarball ships a fully bundled dist/cli.js (node builtins only)
  src = fetchurl {
    url = "https://registry.npmjs.org/@kitlangton/stack/-/stack-${version}.tgz";
    hash = "sha512-4ZY6V8JGDdU6v9aSIrTpY4FUS0zH4tKmQzUpvkqcnLmtcLO4xlJylsSmvxDTYpm+c2pFpjQvwP4tprCFfA8DLg==";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/stack-cli
    cp dist/cli.js $out/share/stack-cli/cli.js

    makeWrapper ${lib.getExe nodejs} $out/bin/stack \
      --add-flags $out/share/stack-cli/cli.js

    runHook postInstall
  '';

  meta = with lib; {
    description = "Squash-safe stacked PR/MR repair CLI for GitHub and GitLab, agent-first";
    homepage = "https://github.com/kitlangton/stack";
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "stack";
  };
}
