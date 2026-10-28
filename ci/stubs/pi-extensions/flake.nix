{
  # CI stub for the private jordangarrison/pi-extensions flake, which is
  # fetched over SSH and unreachable from credential-less GitHub-hosted
  # runners. It mirrors only the interface this repo consumes (see
  # hosts/endeavour/jagpi.nix): packages.<system>.claude-bridge, with the
  # passthru.jagpiProvider path jagpi's module reads. If that surface grows,
  # grow this stub to match.
  description = "CI stub for the private jordangarrison/pi-extensions flake";

  outputs =
    { self }:
    let
      stubFor = system: rec {
        claude-bridge =
          derivation {
            name = "pi-claude-bridge-stub";
            inherit system;
            builder = "/bin/sh";
            args = [
              "-c"
              "echo ci-stub > $out"
            ];
          }
          // {
            jagpiProvider = "lib/node_modules/@jordangarrison/pi-claude-bridge/dist/hosts/jagpi.js";
          };
        default = claude-bridge;
      };
    in
    {
      packages.x86_64-linux = stubFor "x86_64-linux";
      packages.aarch64-darwin = stubFor "aarch64-darwin";
    };
}
