{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.65.0";

  # Datadog ships statically-linked release binaries per platform.
  sources = {
    "x86_64-linux" = {
      suffix = "Linux_x86_64";
      hash = "sha256-mTgsLtfyXNjbELq3NRIgj+SczGgdxGcd/NSBYxuKFSI=";
    };
    "aarch64-linux" = {
      suffix = "Linux_arm64";
      hash = "sha256-NcrEY29vGhavBS18BeQRGdFCj6sw8BalPlQdMCsWqFk=";
    };
    "x86_64-darwin" = {
      suffix = "Darwin_x86_64";
      hash = "sha256-KPOiI5GFkWWdxq3suB0d4R9qRq50MEZiROqlqasJ5yk=";
    };
    "aarch64-darwin" = {
      suffix = "Darwin_arm64";
      hash = "sha256-5oSHJ5mQaWyChuc39p5eHoPicU5UMmigggnJm47nWjE=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "pup: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "pup";
  inherit version;

  src = fetchurl {
    url = "https://github.com/DataDog/pup/releases/download/v${version}/pup_${version}_${source.suffix}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 pup $out/bin/pup
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/pup --version | grep -F "${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "AI-agent-ready CLI for Datadog's observability platform";
    homepage = "https://github.com/DataDog/pup";
    license = lib.licenses.asl20;
    mainProgram = "pup";
    platforms = lib.attrNames sources;
  };
}
