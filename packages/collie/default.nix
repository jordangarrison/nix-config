# ColliePWA (https://github.com/AltanS/collie): a phone web UI for herdr.
#
# Wraps the release tarball, like upstream's own packaging/nix/collie.nix.
# A source build needs `bun install` with network access, so upstream ships no
# sandboxed build and neither do we. Hashes are the sha256 values from the
# release's collie-<version>.manifest.json.
#
# Layout matters: the binary resolves its install root as
# dirname(dirname(realpath(argv0))) and serves web/dist from there, so the
# whole tarball lands in $out/lib/collie and $out/bin/collie is a symlink into
# it. A read-only store path makes Collie classify itself as a packaged install,
# so `collie update` declines and defers to Nix.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "1.22.0";

  sources = {
    "x86_64-linux" = {
      platform = "linux-x64";
      sha256 = "4cb56e52f5d3e9f5f4de17701cf619ed0d878cb70bd570337e4a30100d10b7e5";
    };
    "aarch64-linux" = {
      platform = "linux-arm64";
      sha256 = "b9bf73c21633a9f616e20cd18630e1d884b9e260c8b45f52e8d390ecc47b5942";
    };
    "aarch64-darwin" = {
      platform = "macos-arm64";
      sha256 = "aea69e7c0811bbbabe2e4da7c78c7c7bf93063d2db5b82858b29bbeed81f6f55";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "collie: no release payload for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "collie";
  inherit version;

  src = fetchurl {
    url = "https://github.com/AltanS/collie/releases/download/v${version}/collie-${version}-${source.platform}.tar.gz";
    inherit (source) sha256;
  };

  # A Bun single-file executable built against glibc: on NixOS it needs its
  # interpreter and rpath rewritten.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  dontConfigure = true;
  dontBuild = true;
  # The JS bundle is appended to the ELF image; stripping it breaks startup.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/collie" "$out/bin"
    cp -R ./. "$out/lib/collie/"
    chmod +x "$out/lib/collie/bin/collie"
    [ -d "$out/lib/collie/scripts" ] && chmod +x "$out/lib/collie/scripts"/*.sh
    ln -s "$out/lib/collie/bin/collie" "$out/bin/collie"

    runHook postInstall
  '';

  # Proves the patched binary still reads its embedded bundle and resolves its
  # install root: with a broken layout or missing web bundle, --version still
  # exits 0 but prints `unknown` or `<version> (manifest; web not built)`.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    v=$("$out/bin/collie" --version)
    echo "collie --version: $v"
    [[ "$v" == ${version}+* ]]
    runHook postInstallCheck
  '';

  meta = {
    description = "Self-hosted phone web UI (PWA) for the coding agents running in herdr";
    homepage = "https://github.com/AltanS/collie";
    license = lib.licenses.mit;
    mainProgram = "collie";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
