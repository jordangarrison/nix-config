---
name: herdr-dispatch
description: Dispatch a task into an isolated herdr worktree - create (or reuse) the repo's herdr workspace, cut a worktree workspace off the fresh default branch, start an agent in its pane, and hand off minimal context. The dispatching session stays a coordinator; execution happens in the worktree pane and the user manages it there. Triggered by `/herdr-dispatch`, "dispatch this to a worktree", "spin up a worktree for X", or when a workspace AGENTS.md routes parallel/isolated work to herdr. Requires HERDR_ENV=1 (fall back to the workspace's manual .worktrees/ convention otherwise).
---

# Herdr Dispatch

Send a unit of work to its own herdr worktree + workspace, staffed with an agent, without pulling the current session (or the user's focus) away from what it's doing.

**The dispatcher does not implement the task.** It creates the isolated environment, passes context, and reports back. All edits happen in the worktree's pane, managed by the user from there.

## When to use

- A task needs an isolated branch/checkout (feature work, a review, a risky experiment) and the session is running inside herdr.
- A multi-repo change needs one worktree per repo, each with its own agent and its slice of the context.

**Do NOT use** for quick edits in the current checkout, or outside herdr (`HERDR_ENV` unset) - use the workspace's manual `.worktrees/` fallback instead.

## Inputs

- **Task** (required): what the worktree agent should do. A ticket id counts.
- **Repo(s)**: resolve via the workspace AGENTS.md routing table if not given; ask if ambiguous.
- **Agent kind**: default `claude`; honor an explicit request (`codex`, etc. - `herdr agent` lists installed kinds).
- **Branch name**: default to the ticket's suggested branch (Linear style, e.g. `jordangarrison/sre-123-slug`) in ticketed workspaces, otherwise a short conventional slug (`fix-pool-leak`).

## Steps

Load the [[herdr]] skill first for CLI mechanics - discover syntax from the installed binary, parse all IDs from JSON responses, never predict them. Use `--no-focus` on every create.

1. **Route + read**: identify the target repo; read its `CLAUDE.md` enough to know the default branch and any env-file quirks.
2. **Freshness**: `git -C <repo> fetch --all --prune`. The worktree must branch from the just-fetched remote head.
3. **Repo workspace (reuse-or-create)**: find an existing workspace via `herdr workspace list` (match `worktree.repo_root` to the repo's absolute path); only if missing, `herdr workspace create --cwd <repo> --label <repo> --no-focus`.
4. **Create the worktree**:
   ```bash
   herdr worktree create --workspace <repo-ws-id> \
       --branch <branch> --base origin/<default-branch> \
       --label "<label>" --no-focus --json
   ```
   Label: `<TICKET> <short desc>` in ticketed workspaces, otherwise a short task description. Read `.result.worktree.path` (checkout) and `.result.root_pane.pane_id` from the response. Don't pass `--path` - herdr's default (`~/.herdr/worktrees/<repo>/<slug>`) is the convention.
5. **Env files**: copy `.env`, `.env.local`, `.envrc` (and app-scoped env files in monorepos) from the main clone into the checkout. **Always `direnv allow <checkout>` when an `.envrc` was copied** - without it, direnv refuses the file and dev tooling silently won't activate.
6. **Start the agent** in the worktree's root pane:
   ```bash
   herdr agent start <name> --kind <kind> --pane <root-pane-id>
   ```
   Name it after the task (`[a-z][a-z0-9_-]{0,31}`, unique among live agents, e.g. `playbooks-rp`).
7. **Hand off context** with `herdr agent prompt <name> "..."`. Keep it minimal: the task, the ticket, "read CLAUDE.md first", and any state the agent can't cheaply rediscover (decisions already made, files already touched, known gotchas). For a multi-repo change, pass only that repo's slice. Do not restate worktree mechanics, commit chains, or the full deliverable list.
8. **Verify the prompt actually submitted**: multi-line prompts can land as an unsubmitted paste (`[Pasted text #1 ...]` sitting at the input). Check `herdr agent get <name>` - if status is still `idle`, `herdr agent read <name> --source visible --lines 10` to confirm, then `herdr agent send-keys <name> enter` and re-check for `working`.
9. **Report back**: workspace id + label, agent name, checkout path. Then stand down - coordinate, don't edit the checkout. The user manages the work in the new pane.

For multi-repo dispatch, repeat 1-9 per repo, partitioning the context in step 7.

## Cleanup (later, on request)

- `herdr worktree remove --workspace <id>` removes checkout and workspace together (`--force` only for dirty checkouts, after confirming). Herdr does **not** delete the local branch - follow with `git -C <repo> branch -d <branch>`.
- Close a plain repo workspace with `herdr workspace close <id>` when it's no longer a useful anchor.
- Only remove what this session created unless the user asks for a broader sweep. For "clean up my workspaces": list, cross-check branches against merged PRs, propose, act on confirmation.
