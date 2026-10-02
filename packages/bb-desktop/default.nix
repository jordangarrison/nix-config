{
  lib,
  appimageTools,
  fetchurl,
  makeWrapper,
}:

let
  pname = "bb-desktop";
  version = "0.44.0";
  src = fetchurl {
    url = "https://github.com/get-bb/bb/releases/download/desktop-v${version}/bb-${version}-x86_64.AppImage";
    hash = "sha256-JH9z7oRLa2N4kWt4jqh2qgxmHFT+c2umlx8NHI0SzaU=";
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs = pkgs: [
    pkgs.git
    pkgs.libsecret
  ];
  nativeBuildInputs = [ makeWrapper ];

  extraInstallCommands = ''
    # Keep the existing bb CLI on PATH. Nix owns updates to this package.
    wrapProgram $out/bin/bb-desktop \
      --unset APPIMAGE \
      --set BB_HOST_DAEMON_AUTO_UPDATE 0

    install -Dm644 ${contents}/bb.desktop $out/share/applications/bb-desktop.desktop
    substituteInPlace $out/share/applications/bb-desktop.desktop \
      --replace-fail "Exec=AppRun %U" "Exec=bb-desktop %U" \
      --replace-fail "Icon=bb" "Icon=bb-desktop"
    install -Dm644 ${contents}/bb.png $out/share/icons/hicolor/512x512/apps/bb-desktop.png
  '';

  meta = {
    description = "BB desktop app with its bundled server and host daemon";
    homepage = "https://github.com/get-bb/bb";
    license = lib.licenses.mit;
    mainProgram = "bb-desktop";
    platforms = [ "x86_64-linux" ];
  };
}
