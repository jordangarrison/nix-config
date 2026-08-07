# Plan: Nixify AI-agent CLI configurations

Status: implemented on feat-nixify-agent-configs (2026-08-06); hardened after
a 27-agent adversarial review (see PR description for findings).

Rollout notes:
- The out-of-store symlinks target the main checkout
  (~/dev/jordangarrison/nix-config). Merge/pull this branch there BEFORE
  `nh os test`/`switch` — and note `nh os test` already runs the
  home-manager activation. A pre-link activation guard now fails the
  home-manager activation with a clear message if any live path is missing
  (override once with AGENTS_LIVE_ALLOW_DANGLING=1 if intentional).
- Post-activation verification checklist: `claude` sees the global
  instructions (symlinked CLAUDE.md); codex loads ~/.codex/AGENTS.md and
  rules through the symlinks (codex has a history of symlink quirks —
  verify, don't assume); statusline renders ($HOME/.claude/statusline.sh);
  `herdr integration status` still green; codex still records new trust
  entries in config.toml.
- Merge scripts skip (with a warning) rather than abort when
  settings.json/config.toml is corrupt, and the codex merge only rewrites
  the file when a declared key actually drifts (a rewrite re-serializes
  the TOML: comments stripped, keys reordered — accepted trade-off).
Date: 2026-08-06
Branch: feat-nixify-agent-configs

## Goal

Manage the hand-authored parts of the Claude Code (`~/.claude`), Codex
(`~/.codex`), and pi (`~/.pi/agent`) configurations declaratively via
home-manager, plus the global and workspace-level CLAUDE.md/AGENTS.md files —
without breaking the files those tools (and herdr) mutate at runtime.

## Inventory & classification

### `~/.claude` (Claude Code)

| Path | Class | Disposition |
|---|---|---|
| `CLAUDE.md` | static, hand-authored (byte-identical to `~/.codex/AGENTS.md`) | **manage** — single source, fan out |
| `settings.json` | **hybrid**: declarative keys (model, theme, statusLine, attribution, effortLevel, env/OTEL…) + runtime-mutated keys (`permissions.allow` ~139 entries, `enabledPlugins`, `hooks` rewritten by herdr integration install) | **managed-merge** (see design) — must stay a writable regular file |
| `settings.local.json` | runtime-accumulated ("always allow", skillOverrides) | leave unmanaged |
| `keybindings.json` | does not exist today | module option available; nothing to migrate |
| `hooks/herdr-agent-state.sh` | herdr-owned, version-bumped on herdr releases | leave (herdr + `programs.herdr.integrations` own it) |
| `agents/*.md` (49 files) | bulk-installed by Datadog pup plugin (single timestamp) | leave — tool-managed |
| `skills/` | already handled: agent-skills fan-out symlinks + skills.sh/plugin-owned dirs | no change |
| `workflows/deep-research-staged.js` | static, hand-authored | **manage** — move into repo, out-of-store symlink |
| `plugins/`, `plans/`, `projects/`, `history.jsonl`, `.credentials*`, daemon/session/cache/etc. | pure runtime state / secrets | leave |

### `~/.codex` (Codex)

| Path | Class | Disposition |
|---|---|---|
| `AGENTS.md` | static, identical to `~/.claude/CLAUDE.md` | **manage** — same single source |
| `config.toml` | **hybrid**: declarative top-level keys (approval_policy, sandbox_mode, model, otel, tui…) + runtime-mutated tables (`[projects."…"] trust_level` written on every new trusted dir, `[hooks.state."…"] trusted_hash` written by codex, herdr touches hook wiring) | **managed-merge**, stays writable, mode 600 |
| `hooks.json` + `herdr-agent-state.sh` | herdr-owned (rewritten on integration install) | leave |
| `rules/default.rules` | static, hand-authored prefix rules | **manage** — out-of-store symlink |
| `skills/` | skills.sh installs + agent-skills fan-out via `~/.agents/skills` | no change |
| `auth.json`, `*.sqlite`, `history.jsonl`, caches, sessions | runtime state / secrets | leave |

### `~/.pi/agent` (pi)

Already nixified via `modules/home/pi` (`settings.json`, `keybindings.json`,
prompts, themes, extensions are store symlinks). Runtime dirs (sessions,
models-store, auth) unmanaged. **No structural change needed.** Optional:
point pi at the shared global instructions if/when pi grows a global
AGENTS.md location.

### Global + workspace instruction files

| Path | Notes |
|---|---|
| `~/.claude/CLAUDE.md` == `~/.codex/AGENTS.md` | identical today — one canonical repo file |
| `~/dev/jordangarrison/AGENTS.md` (+ `CLAUDE.md -> AGENTS.md`) | workspace "router" doc; dir is not a git repo |
| `~/dev/flocasts/AGENTS.md` (+ symlink) | same pattern; **work content — see open question #2** |
| `~/dev/kartingcoach/AGENTS.md` (+ symlink) | same pattern |
| Per-repo CLAUDE.md/AGENTS.md under `~/dev/*/*` | checked into their own repos — out of scope |

## Design

Follow the existing per-tool module pattern (`modules/home/pi`) and the
agent-skills out-of-store-symlink pattern for anything hand-edited often.

### 1. Canonical content lives in the repo

New directory `users/jordangarrison/agents/`:

```
users/jordangarrison/agents/
├── AGENTS.md                  # global instructions (current ~/.claude/CLAUDE.md content)
├── ROUTER.md                  # generic workspace router (see section 4)
├── workspaces/
│   ├── jordangarrison-additions.md
│   └── kartingcoach-additions.md    # flocasts additions stay local/untracked
├── claude/
│   └── workflows/deep-research-staged.js
└── codex/
    └── rules/default.rules

users/jordangarrison/skills/
└── workspace-inventory/       # new skill: generates ~/dev/<ws>/.workspace.json
```

### 2. `modules/home/claude-code/` — new `programs.claude-code`

- `~/.claude/CLAUDE.md` → `mkOutOfStoreSymlink` to live-checkout
  `users/jordangarrison/agents/AGENTS.md` (edits live, no rebuild — same
  trade-off as agent-skills).
- `~/.claude/workflows/<name>` → out-of-store symlinks.
- `settings` option (freeform JSON): **activation-time merge**, not a store
  symlink. A `home.activation` script (after writeBoundary, before herdr's
  integration re-install) does:

  ```
  merged = existing settings.json  (deep-)merged with  declared keys (declared wins)
  ```

  via `jq -s '.[0] * .[1]'`. Only declared keys are asserted; runtime keys
  (`permissions`, `hooks`, `enabledPlugins`, marketplaces) are never declared,
  so herdr and Claude Code keep full ownership of them. File stays regular
  and writable. Idempotent; drift in declared keys is corrected on every
  activation.
- Declared initially: `model`, `theme`, `tui`, `editorMode`, `effortLevel`,
  `alwaysThinkingEnabled`, `attribution`, `includeCoAuthoredBy`, `statusLine`,
  notification/voice toggles, `skillListingBudgetFraction`. (`env` pending
  open question #3.)
- Explicit non-goals documented in the module header: `settings.local.json`,
  `hooks/`, `agents/`, `plugins/` stay unmanaged.

### 3. `modules/home/codex/` — new `programs.codex`

- `~/.codex/AGENTS.md` → out-of-store symlink to the same
  `users/jordangarrison/agents/AGENTS.md` (kills the manual duplication).
- `~/.codex/rules/default.rules` → out-of-store symlink.
- `config` option: same activation-time merge for declared top-level keys
  (`approval_policy`, `sandbox_mode`, `model`, `model_reasoning_effort`,
  `personality`, `[otel]`, `[tui]`…), implemented with a small python
  `tomllib`/`tomli-w` script (nixpkgs python3 + tomli-w) since there is no
  TOML jq in the default set. `[projects]` and `[hooks.state]` are never
  declared → codex keeps writing trust entries freely. Preserve 600 perms.
- `hooks.json` untouched (herdr-owned).

### 4. Workspace AGENTS.md — single generic router + per-folder data files

(Revised per plannotator feedback 2026-08-06.)

One generic, workspace-agnostic router doc tracked in the repo, symlinked
into every workspace. All workspace-specific content lives in two
convention files *next to* the symlink, which the router tells the agent
to read:

```
users/jordangarrison/agents/
└── ROUTER.md                    # the only router doc, fully generic

~/dev/<ws>/
├── AGENTS.md    → out-of-store symlink to <liveDir>/agents/ROUTER.md
├── CLAUDE.md    → symlink to AGENTS.md (as today)
├── .workspace.json              # generated repo inventory (see skill below)
└── ADDITIONS.md                 # optional, workspace-specific conventions
```

ROUTER.md conventions (in priority order):
1. "This folder is a router, not a repo" preamble + generic herdr
   dispatch/cleanup conventions (defer mechanics to the herdr skills).
2. "Read `./.workspace.json` for the repo inventory / routing table.
   If missing or stale, regenerate it with the `workspace-inventory`
   skill."
3. "If `./ADDITIONS.md` exists, read it — it carries this workspace's
   specific conventions (branch/label naming, ticket formats, extra
   dispatch modes) and overrides this file where they conflict."

**`workspace-inventory` skill** (new, in `users/jordangarrison/skills/` —
distributed by the existing agent-skills fan-out): scans sibling repo
directories and (re)generates `.workspace.json`: repo name, one-line
description (first heading/paragraph of the repo's CLAUDE.md/AGENTS.md
or README), primary language, default branch, remote. Replaces the
hand-maintained routing tables, which were the main drift source
(jordangarrison says "~40 repos", flocasts has 56+).

**ADDITIONS.md handling per workspace:**
- `jordangarrison`, `kartingcoach`: content tracked in repo
  (`users/jordangarrison/agents/workspaces/<ws>-additions.md`), planted
  as out-of-store symlinks — live-editable, no rebuild.
- `flocasts`: plain local file, **never enters this repo** (work
  content; repo is public). The router doesn't care whether
  ADDITIONS.md is a symlink or a regular file.

Everything is a symlink or a generated/local file → no rebuild needed
for any router or additions content edit; adding a new workspace is one
entry in a module list + one rebuild to plant symlinks. This matches
the agent-skills pattern exactly and removes the eval-time templating
machinery from the earlier revision of this plan.

### 5. Wiring

Enable in `users/jordangarrison/home.nix` next to `programs.agent-skills`,
reusing the same `liveDir` root convention
(`~/dev/jordangarrison/nix-config/users/jordangarrison/...`).

## Migration steps (implementation order)

1. Copy current live content into `users/jordangarrison/agents/`, `git add`
   (flake eval only sees tracked files). Author ROUTER.md by distilling the
   generic prose from the three existing router docs; split their
   workspace-specific prose into the per-workspace additions files
   (flocasts additions written directly to `~/dev/flocasts/ADDITIONS.md`,
   untracked).
2. Write the `workspace-inventory` skill in `users/jordangarrison/skills/`
   + `git add` (fan-out distributes it); run it once per workspace to seed
   `.workspace.json`.
3. Write modules; `nh os build . --no-nom`.
4. Move aside the existing regular files home-manager would collide with
   (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.codex/rules/default.rules`,
   workspace AGENTS.md files, `~/.claude/workflows/deep-research-staged.js`)
   — hm refuses to clobber unmanaged regular files.
5. `nh os test . --no-nom`; verify: symlinks planted, settings.json merge
   idempotent, `herdr integration status` still green, codex still writes
   trust entries.
6. `nh os switch` only after user confirms.

## What deliberately stays out

- Credentials/auth files, history, sessions, caches, sqlite state.
- herdr hook scripts and hook wiring (owned by `programs.herdr.integrations`).
- pup-installed `~/.claude/agents/` and plugin/marketplace state.
- Per-repo CLAUDE.md files (belong to their repos).
- `settings.local.json` / codex `[projects]` trust — permission accumulation
  is runtime behavior by design.

## Decisions (resolved via plannotator annotations, 2026-08-06)

1. **Merge-on-activation: approved.** Declarative management of settings
   (prompts, model, statusline, etc.) is wanted, but claude/codex/opencode/pi
   must keep the ability to mutate their own settings files. Files stay
   regular and writable; only declared keys are asserted on activation.
2. **flocasts workspace content stays out of the repo.** Resolved by the
   generic-router redesign (section 4): the shared ROUTER.md is public and
   generic; flocasts specifics live in a local, untracked ADDITIONS.md and
   a generated .workspace.json.
3. **Datadog OTEL key: option (a).** The key stays only in the mutable
   settings.json; `env` is never declared in nix and the key is never
   committed (repo is public).
