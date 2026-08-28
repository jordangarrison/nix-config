---
name: herdr-dispatch
description: Dispatch a task into an isolated herdr workspace - for repo work, cut a worktree workspace off the fresh default branch; for investigation-shaped work with no owning repo, create a plain workspace in the workspace's investigations home instead. Proposes a harness, model, and thinking level for the new agent, then starts it in the pane and hands off minimal context. The dispatching session stays a coordinator; execution happens in the new pane and the user manages it there. Triggered by `/herdr-dispatch`, "dispatch this to a worktree", "spin up a worktree for X", or when a workspace AGENTS.md routes parallel/isolated work to herdr. Pass `--yolo` to let the dispatcher pick the harness/model/thinking without confirming. Requires HERDR_ENV=1 (fall back to the workspace's manual .worktrees/ convention otherwise).
---

# Herdr Dispatch

Send a unit of work to its own herdr worktree + workspace, staffed with an agent, without pulling the current session (or the user's focus) away from what it's doing.

**The dispatcher does not implement the task.** It creates the isolated environment, passes context, and reports back. All edits happen in the worktree's pane, managed by the user from there.

## When to use

- A task needs an isolated branch/checkout (feature work, a review, a risky experiment) and the session is running inside herdr.
- A multi-repo change needs one worktree per repo, each with its own agent and its slice of the context.
- An investigation-shaped task (diagnose / quantify / "why is X broken") has no obvious owning repo - use **Investigation mode** below instead of a worktree.

**Do NOT use** for quick edits in the current checkout, or outside herdr (`HERDR_ENV` unset) - use the workspace's manual `.worktrees/` fallback instead.

## Inputs

- **Task** (required): what the worktree agent should do. A ticket id counts.
- **Repo(s)**: resolve via the workspace AGENTS.md routing table if not given; ask if ambiguous.
- **Agent kind**: default to the calling agent's own kind - a dispatch from claude staffs claude, from codex staffs codex, and likewise for opencode, pi, and any other installed kind. Discover your own kind with `herdr agent get "$HERDR_PANE_ID"` (`.result.agent.agent`) instead of assuming. Honor an explicit request for a different kind (`herdr agent` lists installed kinds).
- **Model + thinking level**: propose them; see [Staffing the agent](#staffing-the-agent). Never staff silently on whatever the harness happens to default to - a fresh pane inherits the harness's own default, which drifts and is usually not what this task wants.
- **Branch name**: default to the ticket's suggested branch (Linear style, e.g. `jordangarrison/sre-123-slug`) in ticketed workspaces, otherwise a short conventional slug (`fix-pool-leak`).
- **`--yolo`**: skip the staffing confirmation in step 6 and dispatch on the proposal as-is. Everything else is unchanged - `--yolo` decides the staffing, it does not skip the freshness fetch, the env-file copy, or the prompt-submitted check.

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
6. **Staff and start the agent** in the worktree's root pane. Pick harness/model/thinking per [Staffing the agent](#staffing-the-agent), state the choice in one line, and (unless `--yolo`) let the user correct it before starting:
   ```bash
   herdr agent start <name> --kind <kind> --pane <root-pane-id> -- <agent-args>
   ```
   Everything after `--` is passed straight through to the harness binary, so that is where the model and thinking flags go. Name the agent after the task (`[a-z][a-z0-9_-]{0,31}`, unique among live agents, e.g. `playbooks-rp`). The response echoes the full `argv` - read it back to confirm the flags landed.
7. **Hand off context** with `herdr agent prompt <name> "..."`. Keep it minimal: the task, the ticket, "read CLAUDE.md first", and any state the agent can't cheaply rediscover (decisions already made, files already touched, known gotchas). For a multi-repo change, pass only that repo's slice. Do not restate worktree mechanics, commit chains, or the full deliverable list.
8. **Verify the prompt actually submitted**: multi-line prompts can land as an unsubmitted paste (`[Pasted text #1 ...]` sitting at the input). Check `herdr agent get <name>` - if status is still `idle`, `herdr agent read <name> --source visible --lines 10` to confirm, then `herdr agent send-keys <name> enter` and re-check for `working`.
9. **Report back**: workspace id + label, agent name, checkout path, and the staffing line actually used. Then stand down - coordinate, don't edit the checkout. The user manages the work in the new pane.

For multi-repo dispatch, repeat 1-9 per repo, partitioning the context in step 7. Staffing can differ per repo - a mechanical change in one repo and a hairy one in another do not deserve the same model.

## Staffing the agent

Propose all three - harness, model, thinking level - as one line the user can correct, e.g. `staffing: pi / claude-opus-5 / high`. Under `--yolo`, state the same line and proceed without waiting.

Match the model to the shape of the work, not to the importance of the ticket:

| Work shape | Model | Thinking |
|---|---|---|
| Mechanical and well-specified: codemod, rename, dep bump, generated-file refresh | `claude-sonnet-5` / `gpt-5.6-luna` | low |
| Ordinary feature or refactor in a codebase with clear conventions | `claude-opus-5` / `gpt-5.6-sol` | medium |
| Root-cause debugging, unclear failure, cross-cutting design | `claude-opus-5` / `gpt-5.6-sol` | high |
| Review, audit, or plan where being wrong is expensive | `claude-opus-5` / `gpt-5.6-sol` | xhigh |

Harness defaults to the caller's kind. Deviate when the task has a harness-specific reason - an existing session to resume, a skill that only one kind has installed, or the user asking.

Flag syntax differs per kind. Everything below goes after `--`:

| Kind | Model | Thinking |
|---|---|---|
| `pi` | `--model <provider>/<id>` (e.g. `claude-bridge/claude-opus-5`) | `--thinking <off\|minimal\|low\|medium\|high\|xhigh\|max>`, or fold it in as `--model <provider>/<id>:<level>` |
| `claude` | `--model <alias\|full-id>` (e.g. `opus`, `claude-opus-5`) | `--effort <low\|medium\|high\|xhigh\|max>` |
| `codex` | `-m <model>` (e.g. `gpt-5.6-sol`) | `-c model_reasoning_effort=<level>` |

```bash
herdr agent start playbooks-rp --kind pi --pane w7C:p1 \
    -- --model claude-bridge/claude-opus-5 --thinking high
```

Check `herdr agent read <name> --source visible` after start: pi and codex both show the active model and effort in the footer, which is the cheapest confirmation that the flags took. For a kind not in the table, check its `--help` for the equivalent flags rather than guessing; if it has none, say so in the report instead of pretending the staffing was applied.

## Investigation mode (no worktree)

For investigation-shaped tasks, the workspace AGENTS.md names an investigations home (in flocasts: the `investigations` repo, convention `YYYY-MM-DD-<ticket>-<slug>`, see its `CLAUDE.md`). Replace steps 2-5 with:

1. `mkdir` the dated investigation folder in the investigations home.
2. `herdr workspace create --cwd <folder> --label "<TICKET> <short desc>" --no-focus` - plain workspace; no branch, no worktree, no env files.
3. Continue from step 6 (staff + start agent, hand off, verify, report). The handoff points at the ticket and the investigations `CLAUDE.md`; include pointers to likely-relevant sibling repos if routing recon already found them. Investigations are usually the "unclear failure" row above - staff them at high, not medium.

If the investigation graduates into code changes, run a normal repo dispatch then - findings stay in the investigation folder. Committing/pushing the investigations repo is the user's call; don't do it unasked. Cleanup for these is `herdr workspace close <id>` only - never delete the investigation folder itself.

## Cleanup (later, on request)

- `herdr worktree remove --workspace <id>` removes checkout and workspace together (`--force` only for dirty checkouts, after confirming). Herdr does **not** delete the local branch - follow with `git -C <repo> branch -d <branch>`.
- Close a plain repo workspace with `herdr workspace close <id>` when it's no longer a useful anchor.
- Only remove what this session created unless the user asks for a broader sweep. For "clean up my workspaces": list, cross-check branches against merged PRs, propose, act on confirmation.
