{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
}:

buildNpmPackage rec {
  pname = "pi-acp";
  version = "0.0.26";

  src = fetchFromGitHub {
    owner = "svkozak";
    repo = "pi-acp";
    rev = "v${version}";
    hash = "sha256-F5uwgWbUmbPcJIk6ylNtxNpKpKI+hFSUWxQ7ffrdUWM=";
  };

  npmDepsHash = "sha256-vjz+jvHOq/OdT0MSwha5cbAbRXU2jex6ekfOvKnwZsk=";

  meta = {
    description = "ACP adapter for the Pi coding agent";
    homepage = "https://github.com/svkozak/pi-acp";
    license = lib.licenses.mit;
    mainProgram = "pi-acp";
  };
}
