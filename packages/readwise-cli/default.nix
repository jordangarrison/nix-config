{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "readwise-cli";
  version = "0.5.6";

  src = fetchFromGitHub {
    owner = "readwiseio";
    repo = "readwise-cli";
    rev = "v${version}";
    hash = "sha256-mRAhGETEoAoqVnVne4PuGVRMjZEBIz8m8WVcA0HtfGQ=";
  };

  npmDepsHash = "sha256-eupjqOEE77pNzY9DBJdYdDraJtUVhbojaG/QCW+m+jw=";

  meta = {
    description = "Official command-line interface for Readwise and Reader";
    homepage = "https://github.com/readwiseio/readwise-cli";
    license = lib.licenses.mit;
    mainProgram = "readwise";
    maintainers = [ ];
  };
}
