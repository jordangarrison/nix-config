{
  # CI stub for the private jordangarrison/jagpi flake, which is fetched
  # over SSH and unreachable from credential-less GitHub-hosted runners.
  # It mirrors only the interface this repo consumes (see
  # hosts/endeavour/jagpi.nix): packages.<system>.{default,jagpi}, and
  # homeManagerModules.default with the services.jagpi options the host
  # sets, typed like upstream, that installs the package. If that surface
  # grows, grow this stub to match.
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
          # Typed like upstream, so a misspelled option or a bad value fails
          # CI. environmentFile is here so the Slack follow-up stays one line.
          options.services.jagpi = {
            enable = lib.mkEnableOption "the jagpi daemon (CI stub)";
            instance = lib.mkOption {
              type = lib.types.strMatching "[a-z][a-z0-9-]{0,31}";
              default = "default";
            };
            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            herdr.package = lib.mkPackageOption pkgs "herdr" { };
          };
          config = lib.mkIf cfg.enable {
            home.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
          };
        };
    };
}
