# Workspace router

This file provides guidance to AI coding agents (Claude Code, Codex, pi, etc.)
working from this directory. It is generic — the same router serves every
workspace folder. Workspace-specific data lives in two sibling files it tells
you to read.

## This directory is a router, not a repo

This folder is a **workspace folder** containing independent git repos as
sibling directories. It is **not itself a git repo**. Treat it as a
dispatcher: identify which repo the task belongs to, then operate inside that
repo.

**Every task starts with routing.** When the user gives you a task from this
directory:

1. **Read `./.workspace.json`** — the generated repo inventory (name,
   description, language, default branch, remote). This is the routing table.
   If it is missing, or stale relative to the directories actually present,
   regenerate it with the `workspace-inventory` skill.
2. **Read `./ADDITIONS.md` if it exists** — workspace-specific conventions
   (branch/ticket naming, org specifics, extra dispatch modes, shared
   infrastructure notes). Where it conflicts with this file, **ADDITIONS.md
   wins**.
3. **Identify the target repo** from the inventory, recent session history,
   or by asking the user if ambiguous.
4. **Read the repo's own `CLAUDE.md`/`AGENTS.md`** if present — it takes
   precedence over this file for repo-specific work. If absent, consider
   offering to `/init` one before non-trivial work.
5. **Do work inside that repo** via `cd <repo>` or absolute paths. Do not
   create files at this workspace root. Cross-repo work is fine — state which
   repos you plan to touch and in what order.

If the user's request doesn't clearly map to one repo, ask before guessing.

## Worktree & workspace management with herdr

Sessions here typically run in a pane inside a **herdr** tab and orchestrate
other herdr workspaces, tabs, and agents for parallel work. Herdr owns
worktree mechanics: `herdr worktree create` runs the `git worktree add`
itself and spawns a sidebar workspace rooted at the checkout. This section
documents the workspace *conventions*; the herdr skill documents the
*mechanics*.

**Gate + skill load.** Check `test "${HERDR_ENV:-}" = 1`. If inside herdr,
load the herdr skill first — `/herdr` in Claude Code (Skill tool), `$herdr`
in Codex, or the running agent's equivalent — and follow its CLI-discovery
guidance (`herdr worktree`, `herdr workspace`, parse IDs from JSON responses,
never predict them). If not inside herdr, use the manual fallback at the end
of this section. The **`/herdr-dispatch` skill** packages this whole flow
(create → env files → agent staffing → handoff) — prefer invoking it over
hand-running the steps.

Use `--no-focus` for everything created in the background — keep the user's
focus where it is. Track what this session creates; that's what it is allowed
to clean up.

### Conventions layered on the herdr skill

1. **Freshness rule (create AND open)**: `git -C <repo> fetch --all --prune`
   before any worktree operation.
   - On **create**, always pass `--base origin/<default-branch>` so the
     worktree branches from the just-fetched remote head. The main clone
     stays on its default branch but no longer needs a checkout/pull dance.
   - On **open** (adopting an existing checkout), after the fetch bring the
     worktree's branch current before working: `git -C <checkout> pull
     --ff-only` if it tracks an upstream, otherwise rebase onto
     `origin/<default-branch>` — so resumed work isn't behind on commits and
     doesn't hit avoidable conflicts.
2. **Reuse-or-create the repo workspace**: find an existing workspace for the
   repo via `herdr workspace list` (match `worktree.repo_root` to the repo's
   absolute path). Only if missing, create one anchored at the main clone:
   `herdr workspace create --cwd <this folder>/<repo> --label <repo>
   --no-focus`.
3. **Create the worktree against that workspace** (`herdr worktree create
   --workspace <repo-ws-id> --branch <branch> --base origin/<default-branch>
   --label "<label>" --no-focus --json`):
   - Branch naming: short conventional slug (e.g. `fix-pool-leak`,
     `feat-new-cli-flag`) unless `./ADDITIONS.md` specifies a ticket-based
     scheme — then follow it.
   - Workspace label: a short task description, prefixed with the ticket if
     the workspace uses tickets.
   - Checkout lands under `~/.herdr/worktrees/<repo>/<slug>` (herdr default;
     don't pass `--path`). Read the actual checkout path and new workspace ID
     from the JSON response.
4. **Copy untracked env files, then `direnv allow`**: `.env`, `.env.local`,
   `.envrc` are gitignored and do **not** follow the worktree. Copy whichever
   exist from the main clone into the checkout path (plus app-scoped env
   files like `apps/<app>/.env.local` in monorepos — check `.gitignore` if
   unsure). **Always run `direnv allow <checkout>` whenever an `.envrc` was
   copied** — without it, direnv refuses the file and the dev-shell tooling
   silently won't activate.
5. **Execute in the worktree's pane, not the dispatch session**: the session
   that creates the worktree is a *dispatcher* — it does not implement the
   task itself. Start an agent in the new workspace's root pane (per the
   herdr skill) and pass the context along: for a multi-repo change, only the
   portion of the work that belongs to that worktree; otherwise the full task
   context. The user manages the work in the new pane from there. Handoff
   prompts stay minimal — point at the repo's `CLAUDE.md` and the task (and
   ticket, if any); don't restate deliverables or commit mechanics. The
   dispatch session's remaining job is coordination (and cleanup later), not
   edits in the checkout.
6. **Adopting old checkouts**: existing `.worktrees/<repo>/<slug>` checkouts
   remain valid. Open one as a workspace with `herdr worktree open` (label
   per the convention above), applying the freshness rule first.

### Cleanup — worktrees AND workspaces

- **Worktree workspaces**: when the branch is merged or abandoned, `herdr
  worktree remove --workspace <id>` removes checkout and workspace together.
  Use `--force` only for dirty checkouts, and only after confirming with the
  user. Herdr does **not** delete the local branch — follow with `git -C
  <repo> branch -d <branch>` (remote branch is usually auto-deleted on
  merge).
- **Plain repo workspaces**: close with `herdr workspace close <id>` when no
  longer needed as an anchor. They're cheap to recreate; keeping one per
  actively-worked repo is fine.
- **Scope rule**: only remove/close workspaces, tabs, and panes this session
  created, unless the user explicitly asks for a broader sweep.
- **Periodic tidy**: on request ("clean up my workspaces"), list workspaces,
  cross-check worktree branches against merged PRs, propose the removal
  list, and act only on confirmation.

### Manual fallback (not inside herdr)

For headless/cron/non-herdr sessions, use `.worktrees/` at the workspace
root:

```bash
cd <this folder>/<repo>
git fetch --all --prune
git checkout <default-branch> && git pull --ff-only

cd <this folder>
git -C <repo> worktree add "$(pwd)/.worktrees/<repo>/<slug>" -b <branch-name>
```

Then copy env files + `direnv allow` exactly as in convention 4 above.
Cleanup: `git -C <repo> worktree remove "$(pwd)/.worktrees/<repo>/<slug>" &&
git -C <repo> worktree prune`.

### Notes

- **Do not `git init` or commit anything at the workspace root.**
- Other tools may create worktrees under `~/.grove/`, `~/.orchard/`, or
  `/var/tmp/vibe-kanban/`. Ignore those — herdr and `.worktrees/` conventions
  here are for manually/agent-initiated parallel work only.

## When the routing is unclear

Ask. Then, if useful, grep session history to confirm — Claude Code session
logs live under `~/.claude/projects/`, one directory per absolute working
directory with `/` replaced by `-`:

```bash
ls -t ~/.claude/projects/$(pwd | tr '/' '-')-<repo>/*.jsonl 2>/dev/null | head
```
