{
  # CI stub for the private flocasts/floai flake, which is fetched over
  # SSH and unreachable from credential-less GitHub-hosted runners.
  # It mirrors only the interface this repo consumes (see
  # users/jordangarrison/home.nix): packages.<system>.flo-cli on the
  # systems CI evaluates. If that surface grows, grow this stub to match.
  description = "CI stub for the private flocasts/floai flake";

  outputs =
    { self }:
    let
      stubFor = system: {
        flo-cli = derivation {
          name = "flo-cli-stub";
          inherit system;
          builder = "/bin/sh";
          args = [
            "-c"
            "echo ci-stub > $out"
          ];
        };
      };
    in
    {
      packages.x86_64-linux = stubFor "x86_64-linux";
      packages.aarch64-darwin = stubFor "aarch64-darwin";
    };
}
