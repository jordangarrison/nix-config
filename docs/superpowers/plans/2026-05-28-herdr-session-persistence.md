# herdr Session Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make herdr survive walk-aways and version updates without losing session context, by enabling its persistence knobs declaratively, managing `config.toml` via a new home-manager module, and shipping a Nix-compatible live-handoff helper.

**Architecture:** A new `programs.herdr` home-manager module (modeled on the existing `programs.tea` / `programs.pi` modules) owns herdr's `config.toml`, writing it from a TOML settings attrset and installing the herdr package. A small `herdr-handoff` script package wraps `herdr server live-handoff --import-exe`, which is the only Nix-viable way to keep live pane processes alive across a herdr binary swap (the bundled `herdr update` downloader can't write to `/nix/store`). The existing per-host `userApps.herdr.enable` switch drives the module.

**Tech Stack:** Nix, home-manager, `pkgs.formats.toml`, `lib/mkScript.nix`, herdr 0.6.4 (`pkgs.llm-agents.herdr`).

**Reference spec:** `docs/superpowers/specs/2026-05-28-herdr-session-persistence-design.md`

**Branch:** `feat/herdr-session-persistence` (already created; the design doc is committed there).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `packages/herdr-handoff/herdr-handoff.sh` | Wrapper: trigger live-handoff against the current store-path binary | Create |
| `modules/scripts-overlay.nix` | Register `pkgs.herdr-handoff` via `mkScript` | Modify (add one entry) |
| `modules/home/herdr/default.nix` | `programs.herdr` option surface; writes `config.toml`; installs herdr + helper | Create |
| `users/jordangarrison/home.nix` | Import the module, map `userApps.herdr.enable` → `programs.herdr.enable`, drop the now-redundant package entry | Modify |

**Verification note (Nix, not unit tests):** There is no test runner here. "Verify it fails / passes" means running `nh os build . --no-nom` (validates module evaluation + TOML generation for the whole system) and inspecting generated files. Per repo convention and CLAUDE.md, **`--no-nom` is mandatory** on every `nh` call. Use `nh os test . --no-nom` to apply to the running system for runtime checks; only `nh os switch` when the whole plan is verified, and only after confirming with the user.

---

### Task 1: Create the `herdr-handoff` helper script package

**Files:**
- Create: `packages/herdr-handoff/herdr-handoff.sh`
- Modify: `modules/scripts-overlay.nix` (add entry before the closing `})` of the overlay)

- [ ] **Step 1: Write the wrapper script**

Create `packages/herdr-handoff/herdr-handoff.sh`:

```bash
#!/usr/bin/env bash
# herdr-handoff — migrate the running herdr session onto the current binary,
# keeping live pane processes alive. The Nix-viable alternative to
# `herdr update --handoff` (whose downloader can't write to /nix/store).
#
# Usage: after `nh os switch`, run `herdr-handoff` to hand the running
# server's live panes to the freshly-built herdr binary.
set -euo pipefail

new_exe="$(readlink -f "$(command -v herdr)")"
echo "herdr-handoff: handing off live panes to ${new_exe}"
echo "herdr-handoff: if the protocol is incompatible, herdr will refuse and you should restart instead."
exec herdr server live-handoff --import-exe "${new_exe}"
```

- [ ] **Step 2: Register the package in the scripts overlay**

In `modules/scripts-overlay.nix`, add this entry immediately after the `flarectl-wrapped` block (the last entry, just before the closing `})`):

```nix
      herdr-handoff = mkScript {
        name = "herdr-handoff";
        script = ../packages/herdr-handoff/herdr-handoff.sh;
        deps = with final; [ coreutils ];
        description = "Migrate the running herdr session onto the current binary via live-handoff";
      };
```

- [ ] **Step 3: Verify the package builds**

Run: `nix build .#nixosConfigurations.opportunity.pkgs.herdr-handoff --no-link --print-out-paths 2>&1 | tail -5`
Expected: prints a `/nix/store/...-herdr-handoff` path with no evaluation errors.

(If that attribute path is not exposed, instead verify via the full build in Step 4 of Task 4; the overlay entry alone cannot break unrelated evaluation.)

- [ ] **Step 4: Commit**

```bash
git add packages/herdr-handoff/herdr-handoff.sh modules/scripts-overlay.nix
git commit -m "feat(herdr): add herdr-handoff live-handoff helper package"
```

---

### Task 2: Create the `programs.herdr` home-manager module

**Files:**
- Create: `modules/home/herdr/default.nix`

- [ ] **Step 1: Write the module**

Create `modules/home/herdr/default.nix`:

```nix
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.herdr;
  tomlFormat = pkgs.formats.toml { };
in
{
  options.programs.herdr = {
    enable = mkEnableOption "herdr terminal workspace manager for AI coding agents";

    package = mkOption {
      type = types.package;
      default = pkgs.llm-agents.herdr;
      defaultText = literalExpression "pkgs.llm-agents.herdr";
      description = "The herdr package to install.";
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      example = literalExpression ''
        {
          onboarding = false;
          theme.name = "rose-pine";
          experimental.pane_history = true;
          session.resume_agents_on_restore = true;
        }
      '';
      description = ''
        Settings written to {file}`$XDG_CONFIG_HOME/herdr/config.toml`.

        Because Nix manages this file it becomes a read-only symlink: change
        settings here and rebuild rather than editing them in the herdr UI.
        herdr's mutable runtime state (session.json, session-history.json,
        logs, sockets, release-notes.json) is intentionally not managed and
        stays writable.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
      pkgs.herdr-handoff
    ];

    xdg.configFile."herdr/config.toml" = mkIf (cfg.settings != { }) {
      source = tomlFormat.generate "herdr-config.toml" cfg.settings;
    };
  };
}
```

- [ ] **Step 2: Verify the module file parses**

Run: `nix-instantiate --parse modules/home/herdr/default.nix > /dev/null && echo OK`
Expected: prints `OK` (syntax valid). Full evaluation is exercised in Task 4.

- [ ] **Step 3: Commit**

```bash
git add modules/home/herdr/default.nix
git commit -m "feat(herdr): add programs.herdr home-manager module"
```

---

### Task 3: Wire the module into home.nix and remove the redundant package entry

**Files:**
- Modify: `users/jordangarrison/home.nix` (imports list ~line 27–30; herdr `home.packages` block at lines 234–236)

- [ ] **Step 1: Add the module import**

In `users/jordangarrison/home.nix`, in the `imports = [ ... ];` list (currently ending with `../../modules/home/pi`), add the herdr module:

```nix
  imports = [
    ./tools/nvim/nvf.nix
    ../../modules/home/acp-adapters
    ../../modules/home/languages
    ../../modules/home/pi
    ../../modules/home/herdr
  ];
```

- [ ] **Step 2: Enable and configure herdr near the other `programs.*` blocks**

In `users/jordangarrison/home.nix`, immediately after the `programs.acp-adapters = { enable = true; };` block (around line 84–86), add:

```nix
  programs.herdr = {
    enable = userApps.herdr.enable or false;
    settings = {
      onboarding = false;
      theme.name = "rose-pine";
      ui.agent_panel_scope = "all";
      experimental.pane_history = true;
      session.resume_agents_on_restore = true;
    };
  };
```

- [ ] **Step 3: Remove the now-redundant package entry**

In `users/jordangarrison/home.nix`, delete the three-line herdr block at lines 234–236 (the module now installs the package). Remove exactly:

```nix
    ++ lib.optionals (userApps.herdr.enable or false) [
      llm-agents.herdr
    ]
```

Leave the surrounding `]` (line 233, end of the prior list) and the next `++ lib.optionals (userApps.todoist.enable or false) [` (was line 237) intact and directly adjacent.

- [ ] **Step 4: Verify the whole NixOS config still evaluates and builds**

Run: `nh os build . --no-nom`
Expected: build succeeds with no evaluation errors. Confirm the herdr config derivation is present:

Run: `nh os build . --no-nom 2>&1 | tail -20`
Expected: ends in a successful build (no `error:` lines).

- [ ] **Step 5: Commit**

```bash
git add users/jordangarrison/home.nix
git commit -m "feat(herdr): manage config declaratively via programs.herdr"
```

---

### Task 4: Apply and verify the generated config

**Files:** none (runtime verification).

- [ ] **Step 1: Apply to the running system**

Run: `nh os test . --no-nom`
Expected: activation succeeds.

- [ ] **Step 2: Verify the managed config.toml exists and is correct**

Run: `readlink -f ~/.config/herdr/config.toml`
Expected: resolves to a `/nix/store/...-herdr-config.toml` path (proves it's Nix-managed / read-only).

Run: `cat ~/.config/herdr/config.toml`
Expected: contains exactly these settings (TOML key order may differ):

```toml
onboarding = false

[experimental]
pane_history = true

[session]
resume_agents_on_restore = true

[theme]
name = "rose-pine"

[ui]
agent_panel_scope = "all"
```

- [ ] **Step 3: Verify the handoff helper is on PATH**

Run: `command -v herdr-handoff && herdr-handoff --help 2>&1 | head -3 || true`
Expected: prints the `herdr-handoff` store path. (The script has no `--help`; it will attempt a handoff — so do NOT run it bare yet; just confirm it resolves on PATH.)

- [ ] **Step 4: Reload config into the running server (best effort)**

Run: `herdr server reload-config`
Expected: succeeds. Note: `experimental.pane_history` is a startup-only setting and only takes effect after a server restart (see Task 5); `resume_agents_on_restore` is read at restore time. No commit needed for this task (no file changes).

---

### Task 5: Validate persistence behavior at runtime

**Files:** none (runtime verification). These steps confirm the feature actually works; they involve restarting the herdr server, so run them when it's safe to do so.

- [ ] **Step 1: Validate `pane_history` survives a restart**

In a herdr session, leave some scrollback in a pane, then restart the server:

Run: `herdr server stop` then `herdr` (reattach).
Expected: `~/.config/herdr/session-history.json` now exists, and reopened panes replay recent scrollback.

Run: `test -f ~/.config/herdr/session-history.json && echo "history persisted"`
Expected: prints `history persisted`.

- [ ] **Step 2: Validate agent session restore**

Open a Claude Code pane in herdr, then restart the server (`herdr server stop`; `herdr`).
Expected: the Claude Code pane resumes its prior conversation rather than starting empty. If it restores as a plain shell, check the integration version:

Run: `herdr integration list 2>&1 | head -20`
Expected: shows the Claude Code integration; note its version. Agent resume requires the Claude Code herdr integration "version 4" or newer. If older, record this as a follow-up (a herdr/integration bump) — it does not block parts 1–3.

- [ ] **Step 3: Validate the handoff helper as a same-version no-op**

This proves `server live-handoff --import-exe` works before relying on it across a real version bump. With a running herdr server:

Run: `herdr server live-handoff --import-exe "$(readlink -f "$(which herdr)")"`
Expected: handoff completes (`live handoff completed; old server exiting`) and the client reconnects with panes intact; or it cleanly reports an incompatible/again message. It must NOT leave the session broken. If it succeeds, `herdr-handoff` (the wrapper) is validated by extension.

- [ ] **Step 4: No commit** (verification only).

---

### Task 6: Document the update workflow

**Files:**
- Modify: `CLAUDE.md` (add a short herdr persistence note) — repo root `nix-config/CLAUDE.md`.

- [ ] **Step 1: Add a herdr persistence subsection**

Append a concise note under a suitable section of `nix-config/CLAUDE.md` (e.g. near the development tooling notes). Add:

```markdown
### herdr session persistence

herdr config is managed declaratively by `programs.herdr` (`modules/home/herdr/`),
gated on `userApps.herdr.enable`. `config.toml` is a read-only Nix symlink — change
settings in `users/jordangarrison/home.nix` and rebuild, not in the herdr UI.
`pane_history` and `resume_agents_on_restore` are enabled, so scrollback and agent
conversations survive a server restart (runtime state lives in the unmanaged
`session.json` / `session-history.json`).

**Update workflow (keep live processes across a herdr bump):**
`herdr update --handoff` does not work on Nix (its downloader can't write to
`/nix/store`). Instead:
1. `nh flake update llm-agents` then `nh os switch . --no-nom`
2. `herdr-handoff`  — migrates the running session onto the new store-path binary
   via `herdr server live-handoff --import-exe`, keeping pane processes alive.
If herdr refuses the handoff (incompatible protocol across versions), restart the
server normally; `pane_history` + `resume_agents_on_restore` restore scrollback and
agent conversations.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(herdr): document declarative config and live-handoff update workflow"
```

---

## Self-Review

**Spec coverage:**
- Spec §1 & §2 (enable `pane_history`, `resume_agents_on_restore`) → Task 3 Step 2 (settings), verified Task 4 Step 2 + Task 5 Steps 1–2. ✓
- Spec §3 (declarative `programs.herdr` module, fold in existing settings, leave runtime state alone, drop redundant package entry) → Task 2 + Task 3. ✓
- Spec §4 (`herdr-handoff` helper package via `mkScript` + overlay, installed by module) → Task 1 + module `home.packages` in Task 2, validated Task 5 Step 3. ✓
- Spec testing/verification items → Tasks 4 and 5 (build, symlink inspection, reload-config, restart checks, integration version check, no-op handoff). ✓
- Spec risk "integration version for agent resume" → Task 5 Step 2 records a follow-up. ✓
- Spec out-of-scope items are not implemented. ✓
- Docs note (update workflow) → Task 6 (beyond strict spec, but small and aids the user's stated goal). ✓

**Placeholder scan:** No "TBD"/"TODO"/"handle edge cases". Every code step shows full file contents or the exact snippet and adjacency. ✓

**Type/name consistency:** Option path `programs.herdr.{enable,package,settings}` is consistent across Tasks 2 and 3. `pkgs.herdr-handoff` defined in Task 1, referenced in Task 2 module. `tomlFormat.generate "herdr-config.toml"` name matches the expected `readlink` target shape in Task 4. ✓
