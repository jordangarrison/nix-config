{ lib, stdenvNoCC, makeWrapper }:

{ name
, script
, deps ? []
, description ? ""
, version ? "1.0.0"
, extraInstallPhase ? ""
}:

stdenvNoCC.mkDerivation {
  pname = name;
  inherit version;
  src = builtins.dirOf script;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${builtins.baseNameOf script} $out/bin/${name}
    chmod +x $out/bin/${name}
    ${lib.optionalString (deps != []) ''
      wrapProgram $out/bin/${name} --prefix PATH : ${lib.makeBinPath deps}
    ''}
    ${extraInstallPhase}

    runHook postInstall
  '';
  meta = {
    inherit description;
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = name;
  };
}
