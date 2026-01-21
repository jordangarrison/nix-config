{
  lib,
  stdenvNoCC,
  makeWrapper,
  coreutils,
  gnugrep,
  bash,
}:

stdenvNoCC.mkDerivation {
  pname = "ralph";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ralph.sh $out/bin/ralph
    chmod +x $out/bin/ralph

    wrapProgram $out/bin/ralph \
      --prefix PATH : ${lib.makeBinPath [ coreutils gnugrep bash ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Ralph Wiggum iterative AI loop - runs AI agents until completion";
    homepage = "https://github.com/jordangarrison/nix-config";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.all;
    mainProgram = "ralph";
  };
}
