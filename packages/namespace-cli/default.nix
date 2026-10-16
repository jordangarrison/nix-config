{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.0.576";

  # Namespace ships statically-linked release binaries per platform. nixpkgs'
  # namespace-cli lags upstream releases, so track them directly.
  sources = {
    "x86_64-linux" = {
      suffix = "linux_amd64";
      hash = "sha256-H6iU9rqF30l6g616mouCH7Mx2ir23HsUKULefRQt3fM=";
    };
    "aarch64-linux" = {
      suffix = "linux_arm64";
      hash = "sha256-vsHACpx7cy2bdCZSpBcAchgKxljTWW1144oRs/S/QWo=";
    };
    "x86_64-darwin" = {
      suffix = "darwin_amd64";
      hash = "sha256-i9Z9ERdOIuVCVVQDyirBwpOBBjN6h0l4dtUQ9BUzivc=";
    };
    "aarch64-darwin" = {
      suffix = "darwin_arm64";
      hash = "sha256-QM08x9s4btCDqgqp2YVFlsxv9tFNC8Fjp4X49yFZ5Oc=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "namespace-cli: unsupported platform ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "namespace-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/namespacelabs/foundation/releases/download/v${version}/nsc_${version}_${source.suffix}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin nsc docker-credential-nsc bazel-credential-nsc
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR $out/bin/nsc version | grep -F "v${version}"
    runHook postInstallCheck
  '';

  meta = {
    description = "Command line interface for the Namespace platform";
    homepage = "https://github.com/namespacelabs/foundation";
    license = lib.licenses.asl20;
    mainProgram = "nsc";
    platforms = lib.attrNames sources;
  };
}
