{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  patchelf,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gobject-introspection,
  gtk3,
  harfbuzz,
  libdrm,
  libgbm,
  libGL,
  libsecret,
  libxkbcommon,
  nss,
  nspr,
  pango,
  python3,
  systemd,
  xorg,
}:

let
  version = "1.4.167";

  # Upstream ships electron-builder debs per architecture.
  sources = {
    "x86_64-linux" = {
      arch = "amd64";
      hash = "sha256-MyxACz54nSleaoMT2wARZLwJkNXBG4fR1SPMBPx5JLU=";
    };
    "aarch64-linux" = {
      arch = "arm64";
      hash = "sha256-c504M2gHmoQdMT8Ri2457xDhQ+WW0rwGqFH3LZ7nWv0=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "orca-ide: unsupported platform ${stdenv.hostPlatform.system}");

  # Computer use: the sidecar spawns plain `python3` from PATH to run
  # resources/computer-use-linux/runtime.py, which imports gi and the
  # Atspi-2.0 typelib (Gdk-3.0/GdkPixbuf-2.0 for screenshots).
  computerUsePython = python3.withPackages (ps: [ ps.pygobject3 ]);
  computerUseTypelibs = lib.makeSearchPath "lib/girepository-1.0" [
    at-spi2-core
    gobject-introspection # DBus/cairo core typelibs Atspi and Gdk depend on
    gtk3
    gdk-pixbuf
    pango.out # pango's default output is "bin"; the typelib is in "out"
    harfbuzz
  ];
in
stdenv.mkDerivation {
  # "orca-ide" (upstream's own binary/deb name) — NOT "orca", which would
  # collide with the GNOME screen reader in nixpkgs.
  pname = "orca-ide";
  inherit version;

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-ide_${version}_${source.arch}.deb";
    inherit (source) hash;
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    patchelf
  ];

  # Libraries the bundled Electron links against; autoPatchelf resolves the
  # rest (libffmpeg, libGLESv2, ...) from the app dir itself.
  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libxkbcommon
    nss
    nspr
    pango
    (lib.getLib stdenv.cc.cc)
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
  ];

  # dlopen'd at runtime (safeStorage keyring, GL, udev device events)
  runtimeDependencies = [
    libGL
    libsecret
    (lib.getLib systemd)
  ];

  unpackPhase = ''
    runHook preUnpack
    # plain `dpkg-deb -x` fails in the sandbox trying to restore the
    # setuid bit on the bundled chrome-sandbox (which we don't use anyway)
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  # Prebuilt binaries; stripping would also destroy the Bun payload in
  # resources/agent-browser-linux-*.
  dontStrip = true;
  dontAutoPatchelf = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share
    cp -r opt/Orca $out/share/orca-ide
    cp -r usr/share/icons $out/share/icons

    install -Dm644 usr/share/applications/orca-ide.desktop \
      $out/share/applications/orca-ide.desktop
    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail "/opt/Orca/orca-ide" "orca-ide"

    # LD_LIBRARY_PATH: the bundled ANGLE (libGLESv2.so) dlopens libEGL.so.1
    # itself, so an rpath on the main binary isn't enough.
    makeWrapper $out/share/orca-ide/orca-ide $out/bin/orca-ide \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libGL ]} \
      --prefix PATH : ${lib.makeBinPath [ computerUsePython ]} \
      --prefix GI_TYPELIB_PATH : ${computerUseTypelibs} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    runHook postInstall
  '';

  postFixup = ''
    autoPatchelf $out/share/orca-ide

    # The agent-browser helper is a Bun single-file executable: its bundled JS
    # lives as trailing data in the ELF, and autoPatchelf's rpath rewrite
    # relocates it (degrading the binary to a bare `bun` CLI). Restore the
    # pristine copy and patch ONLY the interpreter — it links nothing but glibc.
    for pristine in opt/Orca/resources/agent-browser-linux-*; do
      name=$(basename "$pristine")
      install -m755 "$pristine" $out/share/orca-ide/resources/"$name"
      patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
        $out/share/orca-ide/resources/"$name"
    done
  '';

  meta = with lib; {
    description = "ADE for working with a fleet of parallel coding agents";
    homepage = "https://www.onorca.dev";
    license = licenses.mit;
    platforms = attrNames sources;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "orca-ide";
  };
}
