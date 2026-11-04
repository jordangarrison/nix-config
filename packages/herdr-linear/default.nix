{
  lib,
  buildGoModule,
  src,
  version,
}:

# Built from the same flake input as the Herdr mod. The mod pins this version
# in LINEAR_VERSION and only skips its GitHub download when that exact path
# is already executable.
buildGoModule {
  pname = "herdr-linear";
  inherit version src;

  vendorHash = "sha256-pWwEK8cdXCBWXgJTs/T4H1yRGq69Po7DxaVwekpdMwU=";

  env.CGO_ENABLED = "0";

  doCheck = false;

  meta = {
    description = "Linear issues for the Herdr app and herdr TUI";
    homepage = "https://github.com/mrolafsson/herdr-linear";
    license = lib.licenses.mit;
    mainProgram = "herdr-linear";
  };
}
