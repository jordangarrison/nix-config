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

## Work placement and delegation

Routing identifies the repo; it does not require a new worker or make this
session coordinator-only. Work here unless the request or workflow calls for
separate workstreams.

For dedicated tickets, threads, workspaces, or multi-repo workstreams, load
[[work-dispatch]] (`work-dispatch/SKILL.md` under the configured skills
home). It owns orchestration-surface selection and runtime guidance. The
starting surface owns dedicated workers; `HERDR_ENV=1` alone does not select
Herdr. Native harness helpers remain available for bounded assistance.

### Repository conventions

- Branch names: short conventional slugs unless `ADDITIONS.md` specifies a
  ticket scheme. Labels: short task descriptions, prefixed with the ticket.
- Use the owning runtime's checkout creation and cleanup mechanisms. Fetch
  before creating a branch from the default branch; use the fresh remote head
  when supported. For dependent work, explicitly select the parent branch.
  If runtime isolation starts at the parent's commit instead, report that
  base and reconcile it before implementation rather than claiming freshness.
- On resume, inspect dirty state and upstream before updating. Preserve local
  changes; use fast-forward updates where possible and ask about divergence.
- Prepare required ignored env files in local checkouts without printing or
  committing secrets. After copying a trusted `.envrc`, run `direnv allow`.
  Remote environments need their own approved secret delivery, not blind copies.
- Remove only resources this run created, unless a broader cleanup is requested.
  Preserve dirty or unpushed work; confirm destructive cleanup. Use the owning
  runtime to remove its managed checkouts, rather than raw git commands.
  Leave other tools' checkouts alone unless explicitly adopting or cleaning
  them up.
- For standalone tools without managed checkouts, `.worktrees/<repo>/<slug>`
  under the workspace root is the manual convention. Create from the fetched
  remote base without changing the main clone's checked-out branch.
- **Do not `git init` or commit anything at the workspace root.**

## When the routing is unclear

Ask. Then, if useful, grep session history to confirm — Claude Code session
logs live under `~/.claude/projects/`, one directory per absolute working
directory with `/` replaced by `-`:

```bash
ls -t ~/.claude/projects/$(pwd | tr '/' '-')-<repo>/*.jsonl 2>/dev/null | head
```
