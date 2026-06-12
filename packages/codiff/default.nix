{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  electron,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "codiff";
  version = "1.3.0";

  src = fetchurl {
    url = "https://github.com/nkzw-tech/codiff/releases/download/v${version}/codiff_${version}_amd64.deb";
    hash = "sha256-anwv31V2KmndtumAFlNnGlCTjpCXgkjIKtlEbRGDzfs=";
  };

  nativeBuildInputs = [ dpkg makeWrapper ];

  unpackPhase = ''
    runHook preUnpack
    # plain `dpkg-deb -x` fails in the sandbox trying to restore the
    # setuid bit on the bundled chrome-sandbox (which we don't use anyway)
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  # The deb bundles Electron + a pure-JS app dir (no native .node modules),
  # so run the app with nixpkgs electron instead of patching the bundled binary.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/codiff
    cp -r usr/lib/codiff/resources/app/. $out/share/codiff/

    install -Dm644 usr/share/applications/codiff.desktop \
      $out/share/applications/codiff.desktop
    install -Dm644 usr/share/pixmaps/codiff.png \
      $out/share/pixmaps/codiff.png

    makeWrapper ${lib.getExe electron} $out/bin/codiff \
      --add-flags $out/share/codiff

    runHook postInstall
  '';

  meta = with lib; {
    description = "Beautiful, minimal, local diff viewer for reviewing Git changes and committing them";
    homepage = "https://github.com/nkzw-tech/codiff";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with sourceTypes; [ binaryBytecode ];
    mainProgram = "codiff";
  };
}
