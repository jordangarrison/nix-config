{
  # CI stub for the private sre-claude-auto-runner flake, which lives on the
  # Tailscale-only Forgejo and is unreachable from GitHub-hosted runners.
  # It mirrors only the interface this repo consumes (see
  # modules/nixos/sre-claude-auto-runner.nix); if that surface grows, grow
  # this stub to match.
  description = "CI stub for the private sre-claude-auto-runner flake";

  outputs =
    { self }:
    {
      nixosModules.default =
        { lib, ... }:
        {
          options.services.sre-claude-auto-runner = {
            enable = lib.mkEnableOption "sre-claude-auto-runner (CI stub)";
            user = lib.mkOption { type = lib.types.str; };
            workspaceDir = lib.mkOption { type = lib.types.path; };
            dryRun = lib.mkOption { type = lib.types.bool; };
            maxParallel = lib.mkOption { type = lib.types.int; };
            path = lib.mkOption { type = lib.types.listOf lib.types.package; };
          };
        };
    };
}
