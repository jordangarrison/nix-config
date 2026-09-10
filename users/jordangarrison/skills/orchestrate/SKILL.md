---
name: orchestrate
description: Declare the current session an orchestrator. From this point on the agent does not do task work itself - it decomposes the request, dispatches each piece to another agent (a herdr worktree pane via herdr-dispatch when inside herdr, an async subagent otherwise), tracks the workers in a small on-disk ledger, and owns integration. Same harness as the caller by default, explicit model per worker, orchestrator keeps whatever model it was launched with. Triggered by `/orchestrate`, "you are the orchestrator", "declare this session an orchestrator", "hand this off, don't do it yourself". Pass `--yolo` to dispatch on proposed staffing without confirming. Works nested - a dispatched worker can itself be told to load this skill.
---

# Orchestrate

A mode switch, not an orchestration system. Loading this skill turns the current session into a coordinator for the rest of the conversation. The coordinator's only outputs are briefs, dispatches, a ledger, and integration decisions.

## The one rule

**The orchestrator never does the task.** It does not edit repo files, run the tests it asked a worker to run, or "just fix this small thing." Every unit of work goes to another agent. A task marked complete with zero dispatch records in the ledger is a failure, not a shortcut.

The orchestrator *may* read anything, run read-only commands, and write under its ledger directory (see Step 2). It never writes inside a repo checkout.

## Step 0 - know where you are

```bash
test "${HERDR_ENV:-}" = 1 && herdr agent get "$HERDR_PANE_ID"   # .result.agent.agent = own harness kind
```

| Situation | Dispatch backend |
|---|---|
| `HERDR_ENV=1` | **herdr**: one workspace + worktree per writing task via [[herdr-dispatch]] `--yolo`. Read-only helpers (scouting, review) may still use in-process subagents. |
| Not in herdr, harness has async subagents (pi: `subagent` workflowScript with `worktree: true`; claude: Agent tool; codex: subagents) | **in-process**: writers get `worktree: true` or disjoint file ownership; readers run plain. |
| Neither | Say so and stop. Do not fall back to doing the work. |

Model for the orchestrator: whatever this session was launched with - do not switch. Model for each worker: pick explicitly from the staffing table in [[herdr-dispatch]] (mechanical → sonnet/low, ordinary → opus/medium, debugging → opus/high, review → opus/xhigh). Never let a worker inherit silently.

Harness for each worker: the same kind as this session, unless the task names a different one.

Model ids must be exact `provider/model` pairs the harness has enabled. In pi, read `enabledModels` from `~/.pi/agent/settings.json` (today: `claude-bridge/claude-opus-5`, `claude-bridge/claude-sonnet-5`, `openai-codex/gpt-5.6-sol`); a guessed prefix such as `openai/...` fails the child with "No API key found".

## Step 1 - intake

Input is free-form: a sentence, a pasted spec, or a ticket id. If it is a ticket id and a tool for that tracker is available (Linear MCP, `jira` CLI, `tea`), fetch it and use it as source material - but the skill is not coupled to any tracker. No tool? Ask for the text.

Decompose into tasks that can each be owned by one worker with disjoint files. If two tasks must touch the same files, make them one task or sequence them. Keep the count small; three to five concurrent workers is the practical ceiling.

## Step 2 - ledger

The ledger lives **outside every repo** so it can never be committed:

```bash
BASE="${XDG_STATE_HOME:-$HOME/.local/state}/orchestrate/<repo>"
LEDGER="$(ls -d "$BASE/<slug>-"* 2>/dev/null | sort | tail -1)"   # resume the newest run of this slug
LEDGER="${LEDGER:-$BASE/<slug>-$(date +%Y%m%d)}"                # otherwise start today's
mkdir -p "$LEDGER"
```

`<repo>` is the basename of the primary repo, or `misc` when there is none.

`<slug>` is determined in this order:

1. `--slug <name>` on the invocation.
2. The ticket id if the request names one, lowercased (`sre-452`, `proj-123`).
3. Otherwise derive 2-4 words from the request: kebab-case, `[a-z0-9-]` only, max 40 chars ("add dark mode and fix the flaky login test" → `dark-mode-login-test`). Match what [[herdr-dispatch]] would use for the branch so ledger and branches line up.

The date suffix is today's date on creation and is what lets the same slug be run again later. The snippet above resumes the newest existing run of the slug; pass `--fresh` to force a new dated directory instead. Print the resolved path once at the start so the user can find it. All paths in briefs and prompts are absolute.

```
$LEDGER/
  ledger.md            # first line: "# orchestrate: <slug>" then one line per task with status
  task-N-brief.md      # what the worker reads
  task-N-report.md     # what the worker writes back
  dispatch.jsonl       # one record per dispatch: task, agent name, workspace id, checkout, branch, model, thinking, ts
```

The ledger is the source of truth. After any context compaction, or on resume, re-read `ledger.md` and `dispatch.jsonl` and `git log` before doing anything. Never re-dispatch a task the ledger says is done.

Status values: `pending | dispatched | blocked | done | done-with-concerns | failed`.

## Step 3 - brief

`task-N-brief.md` is self-contained. A worker with no access to this conversation must be able to act on it.

```
# Task N: <title>
Repo / checkout: <path>           Branch: <name>       Base: origin/<default>
## Objective
## Acceptance criteria         (how the worker knows it is done; tests to run)
## Files you own               (and files you must not touch)
## Decisions already made      (and why - this is what workers most often miss)
## Non-goals
## Report
Write <absolute $LEDGER path>/task-N-report.md, then reply in under 15 lines:
Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
Commits: <shas>
Tests: <one line>
Concerns: <one line or "none">
Do not spawn reviewers or other agents unless this brief says you are an orchestrator.
```

If the task is itself big enough to need a coordinator, add one line at the top of the brief: *"Load the `orchestrate` skill before starting; you are an orchestrator for this task."* Write it as plain text - slash commands sent through `herdr agent prompt` are often not interpreted as commands.

## Step 4 - dispatch

**herdr:** run [[herdr-dispatch]] `--yolo` per task. Its handoff prompt is five lines: the brief path, "read CLAUDE.md first", the ticket id if any, the report path, and the reply contract. Nothing else - do not paste history. Append the returned workspace id, checkout, branch, agent name, model, and thinking to `dispatch.jsonl`. Verify the prompt actually submitted (herdr-dispatch step 8).

**in-process:** launch one async child per task with the brief as the task text and the same report contract. Writers get `worktree: true`. Record the run id in `dispatch.jsonl`.

Under `--yolo`, dispatch on the proposed staffing line without waiting. Without it, state the staffing line per task once and proceed unless corrected.

## Step 5 - supervise

Do not sit in a silent open-ended wait. Do not poll every few seconds.

- **In-process children** deliver their own completion; continue local work and act when the result arrives.
- **herdr workers, pi orchestrator:** arm one `until` watch per worker with `intervalSeconds: 5` (never the 30s default) and a `timeoutSeconds` matching the task's expected length. Wake when the report file exists **or** the agent is no longer `working`:
  ```bash
  test -f <ledger>/task-N-report.md || herdr agent get <name> | jq -e '.result.agent.agent_status != "working"' >/dev/null
  ```
  Never watch for `done` specifically: herdr reports `idle` or `done` for the same finished state depending on whether a client has already marked it seen, so a `done`-only watch can spin forever on a worker that finished long ago. Arm the watch only after the dispatch prompt was confirmed `working` (herdr-dispatch step 8), otherwise the pre-prompt `idle` fires immediately.

  On wake: report file present → read it and proceed. `blocked` → handle below. Settled with no report → send one closed-ended status prompt and re-arm.

  Yield to the user between wakes; re-arm after handling any wake that does not finish the task.
- **herdr workers, other harnesses:** `herdr agent wait <name> --timeout 600000` in bounded stretches, one status line to the user between stretches.

On `blocked`: `herdr agent read <name> --source visible --lines 30`, decide if it is a routine choice (answer it, log the ruling in `ledger.md` as `Ruling: <decision> - <why>`) or a real decision for the user (ask, once, with the exact question).

Status checks are closed-ended: *"Reply with 1) acceptance criteria met? YES/NO 2) current blocker in one line 3) files changed."* Not "how's it going?".

Fix loop per task: retries 1-3 re-prompt the same worker with the specific failure; retry 4 relaunch one model tier up with the same brief; retry 5 stop and surface to the user.

## Step 6 - integrate

Implementation in parallel, integration serial. For each `done` task:

1. Read `task-N-report.md` and the diff (`git -C <checkout> diff origin/<default>...HEAD`).
2. Optional review pass by an in-process reviewer on a different model family.
3. Open the PR (or hand the branch to the user - the request says which). The orchestrator owns push/PR/merge; workers do not.
4. Update `ledger.md`.
5. Clean up only when the branch is pushed and the checkout is clean: `herdr worktree remove --workspace <id>`, then `git branch -d`. Never `--force` unasked. Never remove a dirty or unpushed checkout.

Report to the user with the ledger summary: tasks, status, PR links, open concerns.

## Guardrails

- Orchestrator writes: only under `$LEDGER`. If you catch yourself opening an editor on a repo file, stop and dispatch instead.
- Workers are leaves (`max depth 1`) unless their brief explicitly makes them orchestrators.
- Keep steering text and lifecycle actions separate: steer with `herdr agent prompt`; interrupt with `herdr agent send-keys <name> ctrl+c`, never by sending "/quit" as text.
- Trust the report file for completion, not the pane's `done` heuristic.
- Only remove workspaces this session created.

## Not in scope

No watcher daemon, no ticket adapters, no budgets beyond the fix-loop cap. Add them as separate skills or extensions if the loop proves out.
