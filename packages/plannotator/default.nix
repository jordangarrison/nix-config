{
  lib,
  stdenv,
  fetchurl,
  patchelf,
}:

let
  version = "0.20.1";

  # Upstream ships Bun-compiled single binaries per platform
  sources = {
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha256-CZ9bDrW8bsQN6WposE4TBr6l88uw98lUtp/Z5nWEOgU=";
    };
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha256-OepCxo081rev9QkFosBzCDqdn8gKPD4fBp6fxwzF+3c=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "plannotator: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "plannotator";
  inherit version;

  src = fetchurl {
    url = "https://github.com/backnotprop/plannotator/releases/download/v${version}/plannotator-${source.suffix}";
    inherit (source) hash;
  };

  dontUnpack = true;
  # stripping (and rpath shrinking) discards the Bun payload appended to the ELF
  dontStrip = true;
  dontPatchELF = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ patchelf ];

  # Bun single-file executables keep their bundled JS as trailing data in the
  # ELF. autoPatchelfHook's rpath rewrite relocates it and the binary degrades
  # to a bare `bun` CLI — patch ONLY the interpreter, which leaves it intact.
  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/plannotator
  '' + lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} $out/bin/plannotator
  '' + ''
    runHook postInstall
  '';

  # Agent integrations (Claude Code plugin, skills, hooks) are installed
  # in-agent, e.g. `/plugin marketplace add backnotprop/plannotator` —
  # this package only provides the CLI/server binary.
  meta = with lib; {
    description = "Local browser-based plan annotation and code review surface for AI coding agents";
    homepage = "https://github.com/backnotprop/plannotator";
    license = licenses.mit;
    platforms = builtins.attrNames sources;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "plannotator";
  };
}
