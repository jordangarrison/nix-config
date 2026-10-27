{
  # CI stub for the private jordangarrison/jagpi flake, which is fetched
  # over SSH and unreachable from credential-less GitHub-hosted runners.
  # It mirrors only the interface this repo consumes (see
  # hosts/endeavour/jagpi.nix): packages.<system>.{default,jagpi}, and
  # homeManagerModules.default with a services.jagpi that accepts any
  # settings and installs the package. If that surface grows, grow this
  # stub to match.
  description = "CI stub for the private jordangarrison/jagpi flake";

  outputs =
    { self }:
    let
      stubFor = system: rec {
        jagpi = derivation {
          name = "jagpi-stub";
          inherit system;
          builder = "/bin/sh";
          args = [
            "-c"
            "echo ci-stub > $out"
          ];
        };
        default = jagpi;
      };
    in
    {
      packages.x86_64-linux = stubFor "x86_64-linux";
      packages.aarch64-darwin = stubFor "aarch64-darwin";

      homeManagerModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.services.jagpi;
        in
        {
          options.services.jagpi = lib.mkOption {
            type = lib.types.submodule {
              freeformType = lib.types.attrsOf lib.types.anything;
              options.enable = lib.mkEnableOption "the jagpi daemon (CI stub)";
            };
            default = { };
          };
          config = lib.mkIf cfg.enable {
            home.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
          };
        };
    };
}
