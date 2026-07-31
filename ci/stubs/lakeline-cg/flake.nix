{
  # CI stub for the private lakeline-cg flake, which lives on the
  # Tailscale-only Forgejo and is unreachable from GitHub-hosted runners.
  # It mirrors only the interface this repo consumes (see
  # modules/nixos/lakeline-cg.nix and flake.nix); if that surface grows,
  # grow this stub to match.
  description = "CI stub for the private lakeline-cg flake";

  outputs =
    { self }:
    {
      nixosModules.default =
        { lib, ... }:
        {
          options.services.lakeline-cg = {
            enable = lib.mkEnableOption "lakeline-cg static site (CI stub)";
            package = lib.mkOption {
              type = lib.types.package;
              description = "lakeline-cg site package (CI stub)";
            };
          };
        };

      packages.x86_64-linux.default = derivation {
        name = "lakeline-cg-stub";
        system = "x86_64-linux";
        builder = "/bin/sh";
        args = [
          "-c"
          "echo ci-stub > $out"
        ];
      };
    };
}
