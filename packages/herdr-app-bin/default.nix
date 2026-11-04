# Signed Herdr desktop app from the official release, for macOS only.
# llm-agents builds herdr-app from source, but on macOS it ships only
# bin/herdr-app: no Herdr.app bundle, so the app is missing from
# ~/Applications. Remove this package once llm-agents ships a bundle.
#
# `version` comes from llm-agents (see modules/home/herdr-app/package.nix),
# so a switch installs the same release that Linux runs. After that, the
# bundle updates itself (Home Manager copies apps, so the copy is writable);
# the next switch puts the llm-agents version back. App versions on different
# machines need not match: compatibility follows herdr-core.
#
# When llm-agents moves to a version that is not in `hashes`, evaluation
# fails. To add it, read the sha256 for
# macos-aarch64 from https://releases.herdr.dev/app/latest.json (or run
# `nix store prefetch-file <url>`), then
# `nix hash convert --hash-algo sha256 --to sri <sha256>`.
{
  lib,
  stdenvNoCC,
  fetchurl,
  version,
}:

let
  hashes = {
    "0.1.11" = "sha256-fE5zGMVLvL8XX/1tG09hi1kTc4MzCv+OtbwQ3D/u7Lk=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "herdr-app";
  inherit version;

  src = fetchurl {
    url = "https://releases.herdr.dev/app/${version}/herdr-app-macos-aarch64.tar.gz";
    hash =
      hashes.${version} or (throw ''
        herdr-app-bin: no release hash for herdr-app ${version}, the version llm-agents ships.
        Add it to `hashes` in packages/herdr-app-bin/default.nix.
      '');
  };

  sourceRoot = ".";

  # Keep the bundle byte-for-byte: macOS permissions follow its signature.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    cp -R Herdr.app $out/Applications/
    ln -s $out/Applications/Herdr.app/Contents/MacOS/Herdr $out/bin/herdr-app
    runHook postInstall
  '';

  meta = {
    description = "Herdr desktop app for terminals and coding agents";
    homepage = "https://herdr.dev";
    license = lib.licenses.asl20;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "herdr-app";
  };
}
