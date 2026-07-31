# ADR 005: PR CI via Nix Evaluation on GitHub-Hosted Runners

## Status

Accepted

## Date

2026-07-31

## Context

Before this ADR the repository had exactly one workflow (`update-flake-lock.yml`,
the daily dependency-bump PR bot) and **no pull-request validation at all**. A PR
could delete a module, break an option reference, or introduce a syntax error and
merge green. Breakage only surfaced when a machine ran `nh os build` locally.

### Requirements

1. Validate every PR against all six configurations: four NixOS hosts
   (endeavour, opportunity, voyager, discovery — all x86_64-linux), one
   nix-darwin host (H952L3DPHH — aarch64-darwin), and one standalone Home
   Manager config (jordangarrison@normandy).
2. Use GitHub-hosted runners; no self-hosted infrastructure in the critical path.
3. Fail with actionable, per-configuration attribution.

### Constraints

1. **Full builds are infeasible on hosted runners.** Each NixOS host closure
   includes a GNOME desktop (plus Niri, media services, several toolchains).
   Building even one from a cold cache exceeds hosted-runner disk (~14 GB
   usable) and would take hours.
2. **Two flake inputs are private and network-unreachable from CI.**
   `lakeline-cg` and `sre-claude-auto-runner` are fetched over SSH from the
   Forgejo instance on endeavour, which is only reachable inside the
   Tailscale network. Nix fetches *every* input in the lock closure during
   flake evaluation, so these two inputs block all CI evaluation — even for
   configurations that never use them.

## Decision

### Evaluation, not builds

Each configuration is evaluated to its top-level derivation path:

```bash
nix eval --raw ".#nixosConfigurations.<host>.config.system.build.toplevel.drvPath"
nix eval --raw ".#darwinConfigurations.H952L3DPHH.config.system.build.toplevel.drvPath"
nix eval --raw '.#homeConfigurations."jordangarrison@normandy".activationPackage.drvPath'
```

Forcing `drvPath` runs the complete module-system evaluation and instantiates
every derivation in the system closure. This catches syntax errors, undefined
options, type errors, removed/renamed packages, and broken module wiring —
the overwhelming majority of real regressions in this repo — in minutes
instead of hours. What it does *not* catch is build failures inside individual
packages (e.g. an upstream source hash mismatch); that residual risk is
accepted and still covered by the local `nh os build → test → switch` flow.

`nix flake check` was rejected: it evaluates everything in one serial job
(worse failure attribution, no parallelism) and does not understand
`darwinConfigurations` or `homeConfigurations` outputs anyway.

### Stub overrides for the private inputs

CI swaps the two Tailscale-only inputs for local stub flakes committed under
`ci/stubs/`:

```
--override-input lakeline-cg path:./ci/stubs/lakeline-cg
--override-input sre-claude-auto-runner path:./ci/stubs/sre-claude-auto-runner
--no-write-lock-file
```

Each stub mirrors **only the interface this repo consumes**: the option
declarations set by `modules/nixos/lakeline-cg.nix` /
`modules/nixos/sre-claude-auto-runner.nix`, plus a dummy
`packages.x86_64-linux.default` derivation for lakeline-cg. If the consumed
surface grows, the stub must grow with it — the eval failure that results is
the reminder.

Alternatives considered:

| Alternative | Why rejected |
|-------------|--------------|
| Join the tailnet from CI (ephemeral Tailscale key + SSH deploy key secrets) | Real coverage of the private inputs, but hands network access to the home LAN and Forgejo credentials to every PR run; heavy secret management for two small inputs |
| Self-hosted runner on endeavour | Full network access and warm nix store, but puts personal hardware in the path of PR code execution; endeavour is also the machine being configured |
| Skip endeavour in CI | Loses eval coverage of the largest, most service-heavy host — the one most likely to break |

The stubs keep CI hermetic and cover ~everything except the two private
modules themselves. If deeper coverage of those inputs is ever needed, a
Forgejo-side runner (forgejo-runner already exists on endeavour) can validate
them inside the tailnet without exposing anything to GitHub.

### macOS coverage on `macos-latest`

The darwin configuration is evaluated on a `macos-latest` (arm64) runner,
matching the host's `aarch64-darwin` platform. Pure evaluation would likely
also succeed on Linux, but running it on macOS keeps the check faithful
(platform-conditional module paths, `stdenv.hostPlatform` branches) at the
cost of a slightly slower runner.

### Fast syntax gate

A separate job runs `nix-instantiate --parse` over every `.nix` file. It is
redundant with the eval jobs for imported files but returns in ~1 minute,
gives per-file error annotations, and also covers files not imported by any
configuration.

## Consequences

- Every PR now gets six independent green/red signals with per-configuration
  attribution; `fail-fast` is disabled so one broken host doesn't mask others.
- Evaluation of a large NixOS config on a cold runner takes roughly 5–15
  minutes (input fetching dominates); timeouts are set at 45 minutes.
- Package-level build failures still pass CI; the local
  `nh os build → test → switch` discipline remains the last line of defense.
- The `ci/stubs/` flakes are a maintained artifact: changing what the repo
  consumes from the private inputs requires updating the matching stub.
- All actions in both workflows are pinned to reviewed full commit SHAs
  (with a `# vN` comment naming the release) rather than mutable tags or
  `@main`, so upstream action changes cannot execute in CI without a
  repository change. Bumping an action means updating the SHA and comment
  together.
