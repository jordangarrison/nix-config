# Signed, notarized upstream Hex.app for Apple silicon; not nixpkgs.hex
# (the unrelated hex dump tool). Upstream's Nix flake supports Linux only.
#
# To update, change version and add the ZIP's SHA256 from the GitHub release
# assets (or `nix store prefetch-file <url>`) to hashes. Convert a hex digest
# with `nix hash convert --hash-algo sha256 --to sri <sha256>`.
# Home Manager copies the bundle: Hex can update that writable copy itself,
# and the next activation restores this pinned version. See README.md.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  version ? "3.4.0",
}:
let
  hashes = {
    "3.4.0" = "sha256-GrAkLcO7ARyIVokDy/Hp0wMQhnpG9RaDCYU9b4tMplA=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "hex-dictation";
  inherit version;

  src = fetchurl {
    url = "https://github.com/anomalyco/hex/releases/download/v${version}/hex-${version}-macos-arm64.zip";
    hash =
      hashes.${version} or (throw ''
        hex-bin: no release hash for Hex ${version}.
        Add it to `hashes` in packages/hex-bin/default.nix.
      '');
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";

  # macOS privacy grants follow the upstream signature. Do not strip,
  # rewrite Mach-O paths, or re-sign any part of the bundle.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications $out/bin
    cp -R Hex.app $out/Applications/
    ln -s $out/Applications/Hex.app/Contents/MacOS/hex $out/bin/hex
    runHook postInstall
  '';

  meta = {
    description = "Local voice dictation";
    homepage = "https://anoma.ly/hex/";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "hex";
  };
}
