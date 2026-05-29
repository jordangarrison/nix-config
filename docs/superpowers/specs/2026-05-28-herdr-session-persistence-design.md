# herdr session persistence — design

**Date:** 2026-05-28
**Status:** Approved (pending spec review)
**Scope:** Make herdr survive walk-aways and version updates without losing session context, and manage its config declaratively in this repo.

## Problem

herdr is installed via Nix (`llm-agents.herdr`, v0.6.4) and enabled per-host through
`userApps.herdr.enable` (endeavour, opportunity, and the work Darwin host). Its config at
`~/.config/herdr/config.toml` is hand-edited and currently sets only `onboarding`, `theme`,
and `ui.agent_panel_scope`. **None of herdr's persistence features are enabled.**

herdr runs panes in a background server. On a server restart it restores only the session
*shape* (workspaces, tabs, panes, working dirs, focus). By default it discards:

- running processes / shells,
- terminal scrollback contents,
- agent conversations (Claude Code, Codex, etc.).

The user's goal: *"walk away from my computer or update herdr and come back and jump right
back in."* Today an update (or reboot) wipes everything but the layout.

## Key constraint and the handoff finding

herdr ships `herdr update --handoff`, which keeps live panes alive across a self-update. Its
docs say package-manager installs (Homebrew, **Nix**) can't use it — because `herdr update`
downloads and writes a new binary, which the immutable `/nix/store` forbids
(`installed remote binary to ~/.local/bin/herdr`).

**However**, direct inspection of the v0.6.4 binary shows the handoff is a *separable*
subcommand, not bound to the downloader:

```
herdr server live-handoff [--import-exe <path>] [--expected-protocol <n>] [--expected-version <version>]
```

- `--import-exe <path>` lets the caller supply the new binary — no download step.
- It transfers each pane's PTY master file descriptor to the new server over the unix socket
  via `SCM_RIGHTS` (`handoff fd message missing SCM_RIGHTS`,
  `struct HandoffPane { child_pid, … }`); **child processes are adopted, not restarted**
  (`preserving pane runtime for handoff`).
- It is version/protocol gated (`HandoffManifest { source_version, source_protocol,
  expected_protocol }`; `live handoff was requested, but no compatible server responded`). A
  herdr bump that crosses a protocol boundary will *refuse* the handoff and the user falls back
  to a normal restart — safe degradation, not a crash.

So on Nix the handoff is reachable by supplying the freshly-built store-path binary:

```sh
herdr server live-handoff --import-exe "$(readlink -f "$(which herdr)")"
```

The old server spawns the new store-path binary and hands off the live panes. Only the
*download* step is Nix-hostile; the handoff itself is not.

> Caveat: this is a manual invocation of an internal subcommand. Treat it as best-effort. It
> has not been runtime-tested end-to-end; evidence is the binary's own usage strings and
> symbols. Validate with a same-version no-op handoff before relying on it across a real bump.

## Layered guarantee (what the user gets)

| Scenario | Mechanism | What survives |
|---|---|---|
| Walk away (no restart) | `ctrl+b q` detach → reattach with `herdr` | **Everything** — processes, scrollback, agents |
| Update herdr | `herdr-handoff` helper (part 4) | Live processes, layout, scrollback, agents — when protocol-compatible |
| Reboot / crash / incompatible bump | snapshot restore + `pane_history` + `resume_agents_on_restore` | Layout, dirs, **scrollback**, **agent conversations** — *not* live processes |

Live OS processes cannot survive a true restart on any install; that is unavoidable and
out of scope.

## Design

Four parts. Parts 1–3 are the core; part 4 is the handoff helper.

### 1 & 2. Enable the persistence knobs

```toml
[experimental]
pane_history = true                 # scrollback survives a full restart

[session]
resume_agents_on_restore = true     # supported agents resume their native session
```

Accepted tradeoff: `pane_history` writes terminal contents (possibly secrets/tokens) to
`~/.config/herdr/session-history.json` in plaintext. This is why herdr ships it off by
default. The user has accepted this.

### 3. Declarative config via a `programs.herdr` home module

New module `modules/home/herdr/default.nix`, modeled on the existing `programs.tea` module.

- Options: `programs.herdr.enable`, `programs.herdr.package` (default: the herdr package
  currently referenced as `llm-agents.herdr` in `home.nix`), and `programs.herdr.settings`
  (a TOML attrset via `pkgs.formats.toml { }`).
- `config = mkIf cfg.enable { ... }` installs the package and writes
  `xdg.configFile."herdr/config.toml"` from `settings`.
- Default `settings` fold in the current hand-edited values plus the new knobs:

  ```nix
  settings = {
    onboarding = false;
    theme.name = "rose-pine";
    ui.agent_panel_scope = "all";
    experimental.pane_history = true;
    session.resume_agents_on_restore = true;
  };
  ```

Wiring:

- Import `../../modules/home/herdr` from `users/jordangarrison/home.nix` (cross-platform —
  the config path is `~/.config/herdr` on both Linux and Darwin).
- Set `programs.herdr.enable = userApps.herdr.enable or false;` so the existing per-host
  switch in `flake.nix` stays the single source of truth.
- Remove the now-redundant `llm-agents.herdr` entry from the `home.packages` list in
  `home.nix` (the module installs it instead). Keep the `userApps.herdr` option definition in
  `nixos.nix` unchanged.

Runtime state files (`session.json`, `session-history.json`, logs, sockets, `release-notes.json`)
are **not** managed — they stay mutable in `~/.config/herdr`.

Accepted tradeoff: a Nix-managed `config.toml` is a read-only symlink, so settings changed
inside the herdr UI won't persist — all config changes go through the repo + rebuild, matching
the model used for every other tool here. (herdr writes its mutable state to the separate files
above, not to `config.toml`, so this does not break herdr's own bookkeeping.)

### 4. `herdr-handoff` helper package

A shell script packaged via `lib/mkScript.nix` and registered in `modules/scripts-overlay.nix`,
matching the existing script-package convention (`myip`, `gi`, `ksn`, …).

- `packages/herdr-handoff/herdr-handoff.sh`:

  ```sh
  #!/usr/bin/env bash
  set -euo pipefail
  new_exe="$(readlink -f "$(command -v herdr)")"
  echo "herdr: handing off live panes to $new_exe"
  exec herdr server live-handoff --import-exe "$new_exe"
  ```

- Register as `herdr-handoff` in `scripts-overlay.nix` (deps: `coreutils` for `readlink`;
  herdr is already on PATH).
- Add to the herdr module's installed packages (alongside `cfg.package`) so it ships wherever
  herdr is enabled.

Intended workflow: `nh flake update llm-agents` → `nh os switch . --no-nom` → then run
`herdr-handoff` to migrate the running session onto the new binary with live processes intact.
If the protocol gate refuses (incompatible bump), herdr aborts/rolls back and the user falls
back to a normal restart, where parts 1–2 restore scrollback + agent conversations.

## Components and boundaries

- **`modules/home/herdr/default.nix`** — owns the `programs.herdr` option surface and writes
  `config.toml`. Depends only on `pkgs.formats.toml` and the herdr package. Testable by
  inspecting the generated symlink target.
- **`packages/herdr-handoff/herdr-handoff.sh`** + overlay entry — one job: invoke
  `server live-handoff` against the current store-path binary. Independent of the module.
- **Wiring in `home.nix`** — maps the existing `userApps.herdr.enable` switch to
  `programs.herdr.enable`. No new host-level option.

## Testing / verification

1. `nh os build . --no-nom`, then `nh os test . --no-nom` (opportunity and/or endeavour). Build
   validates the module and TOML generation.
2. Inspect the result: `cat ~/.config/herdr/config.toml` resolves to the Nix store and contains
   the five settings.
3. Apply without a full restart where possible: `herdr server reload-config`. Note startup-only
   settings (likely `pane_history`) require a server restart to take effect — verify by
   restarting the server and confirming `session-history.json` appears and scrollback replays.
4. Confirm `resume_agents_on_restore` by restarting the server with a Claude Code pane open and
   checking the conversation resumes.
5. Validate the handoff helper as a **same-version no-op** first:
   `herdr server live-handoff --import-exe "$(readlink -f "$(which herdr)")"` on a throwaway
   session — confirms the path/flags work before trusting it across a real bump.

## Risks

- **Read-only config** breaks in-UI settings changes. Mitigated: all config goes through the
  repo; herdr's mutable state lives in separate files.
- **Secrets in `session-history.json`** (accepted).
- **Handoff is an unsupported manual path** — may refuse across protocol-incompatible herdr
  versions, and a failed commit window exists (`handoff replacement server was ready, but commit
  failed`). Mitigated by version gating + rollback, and by falling back to restart + parts 1–2.
- **herdr integration version for agent resume** — Claude Code needs integration "version 4"+.
  Verify with `herdr integration` subcommands during implementation; note if a bump is needed.

## Out of scope

- Keeping live OS processes alive across a true restart/reboot (impossible without handoff, and
  handoff only covers the binary-swap case).
- Remote/SSH handoff (`herdr --remote … --handoff`) — supported by the binary but not part of
  this local-persistence goal.
- Replacing the `herdr update` self-updater; updates continue to flow through the Nix flake.
