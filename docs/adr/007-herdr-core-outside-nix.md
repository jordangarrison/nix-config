# ADR 007: herdr-core Stays Outside Nix

## Status

Accepted

## Date

2026-11-03

## Context

The usual rule (`AGENTS.md`, "Agent tooling") is that agent CLIs come from
`llm-agents` as published, and Nix owns them. The Herdr TUI follows that rule.

The upstream `herdr-app` package (llm-agents.nix #11664) now depends on
`herdr-core` (`hc`) and adds it to the app's PATH. This makes it possible to
let Nix own `herdr-core` too. We examined that option and did not take it:

1. **Remote lookup.** The app reaches other machines over ssh and runs
   `command -v herdr-core || ~/.local/bin/herdr-core`. A Nix copy on PATH
   wins there, so `hc update` and `hc machine update` write to
   `~/.local/bin` and have no effect. Nothing reports the failure.
2. **Long-lived daemon.** `herdr-core serve` and `hold` keep terminals alive.
   A rebuild does not restart them, and `hc server stop` parks the terminals.
   Nix ownership needs a restart step like `herdr-handoff`.
3. **Two installers.** The app installs a missing core into `~/.local/bin`,
   and `hc update` updates it. With Nix ownership, we must stop using both on
   every machine, including other users such as `garrisonsbygrace@voyager`.
4. **Low gain.** `herdr-core` is a static binary. Nix gives pinning and
   rollback, but no dependency management.

## Decision

`herdr-core` is an exception to the agent-tooling rule. It stays
self-managed in `~/.local/bin` on every machine (installed by the app, updated
with `hc update` and `hc machine update`).

- Do not add `herdr-core` to `home.packages` or any other PATH.
- The copy inside the upstream `herdr-app` wrapper is acceptable. The wrapper
  appends it to the end of PATH, so `~/.local/bin` wins.
- `herdr-app` (the GUI) stays Nix-managed from `pkgs.llm-agents.herdr-app`.

## Consequences

- The Nix app and the self-updated core can drift. Upstream pairs them (app
  0.1.11 with core 0.1.17 at this decision). After an `llm-agents` update,
  run `hc update` and `hc machine update` if the core is behind.
- A Nix rollback does not roll back the core.
- Revisit this decision if version drift breaks the app. Then make the Nix
  copy the only one on PATH on all machines, remove the `~/.local/bin`
  copies, and add a server restart step.
