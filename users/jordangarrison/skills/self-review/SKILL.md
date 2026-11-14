---
name: self-review
description: >-
  Use to get a multi-agent review of my own open PR and have its findings fixed
  automatically. From the session that wrote the PR: dispatches a reviewer through [[work-dispatch]] that runs
  [[multi-agent-pr-review]] `--yolo` on the PR (posted as a COMMENT review),
  watches for the result, then fixes or declines every finding in this session
  with [[pr-watch]]'s shared procedure, pushes, and replies on each review
  comment; `--rounds` re-reviews after each push. For other people's reviews,
  use [[pr-watch]]. Triggered by `/self-review`,
  "self-review this PR", "review my PR and fix what it finds".
---

# Self-Review

Reviewer → [[multi-agent-pr-review]] `--yolo` → watcher → fix phase here ([[pr-watch]]'s `address.md`) → optional next round.

This session stays the **author**: it never reviews. The worker is the **reviewer**: it never edits. The watcher is the hand-off between them.

## Inputs

| Input | Default |
|---|---|
| PR URL | `gh pr view --json url` in the current checkout |
| `--rounds <n>` | `1`. Each extra round re-reviews after the fixes are pushed. Max `3`. |
| `--no-push` | Push the fixes. With this flag: commit locally, skip the push and the comment replies. |
| Pi staffing | Pinned to `openai/gpt-6.1-sol:high` for the reviewer and every review helper, including later rounds. |
| `--yolo` | Proceed without interactive gates; staffing is already automatic. |

Invoking the skill is the consent to staff the reviewer, fix, commit, and push. Report staffing for audit; cross-runtime handoffs still require approval unless explicitly preauthorized.

## Steps

### 1. Preflight

All must hold; stop and say which one failed otherwise.

- Read [[work-dispatch]]; retain the current orchestration owner. Choose a native review helper or dedicated reviewer according to the requested lifecycle. Cross-runtime handoffs need approval, even under `--yolo`.
- [[pr-watch]] SKILL.md step 1 (my open PR, clean checkout on its branch, everything pushed). The reviewer reads GitHub, so unpushed work is unreviewed work. Someone else's PR → use [[multi-agent-pr-review]] directly.

Record: `URL`, `OWNER/REPO`, `NUM`, `HEAD` (`gh pr view --json headRefOid`), `DATE` (`date +%F`), `PR_KEY` (`<repo-short>-<num>`, e.g. `ibs-1097`), `RESULT=/tmp/pr-review-$DATE/$PR_KEY/result.json`, `NAME=selfrev-$PR_KEY` (≤ 32 chars, `[a-z0-9-]`).

### 2. Clear stale results

A `result.json` from an earlier run fires the watcher at once. If `$RESULT` exists, rename it to `result.<unix-ts>.json`. Then `mkdir -p` its directory and record a fresh run marker. Before replacing artifacts, confirm no earlier reviewer is still writing there; stop or isolate overlapping runs first.

### 3. Staff the reviewer

In Pi, pin the reviewer to `model: "openai/gpt-6.1-sol:high"` for a native
subagent, or `--model openai/gpt-6.1-sol --thinking high` for a Pi CLI worker.
Use the same pinned staffing for every child review helper and later round,
per [[multi-agent-pr-review]]'s **Reviewer Thinking (pi)** policy. This is the
current staffing until changed; do not select thinking from PR scope or inherit
it from the author. Other harnesses use their supported staffing.

Report the actual staffing. Dispatch with [[work-dispatch]], passing the step 4
brief at launch when required by the tool. Record the worker reference, link,
and completion mechanism. A separate review helper need not become a top-level
thread.

Use a fresh reviewer for follow-ups when the runtime requires it; reuse only
through supported continuation controls. In the Herdr app, a reviewer can run as an
`hc` child, shown in a new unfocused tab in the current space (load
[[herdr-core]] and [[herdr-app]]), without creating an implementation
worktree. The review skill owns its review
checkout. Preserve the author/reviewer separation in every runtime.

### 4. Hand off the review

Send one plain-language prompt (works in every harness; no slash commands):

```
Self-review requested by the PR author. Use the multi-agent-pr-review skill with --yolo on <URL>.
Review head <HEAD>. Write artifacts under /tmp/pr-review-<DATE>/<PR_KEY>/.
This is a self-authored PR: post the review as COMMENT, as the skill describes.
When result.json is written, stop.
```

In Pi, add this instruction to the brief: "Use `model: openai/gpt-6.1-sol:high`
for every review helper, including specialists, lens reviewers, and the
consolidator; keep high thinking for all later rounds." Carry the pinned
staffing into the run context. Do not ask the reviewer to select another
thinking level from PR scope.

Submit using the selected runtime and confirm launch. If the worker cannot
access the author's local artifact directory, arrange supported artifact return
and record the local result path before proceeding.

### 5. Receive completion

Prefer native completion events. For T3 delegates, follow the returned lifecycle
instructions: no polling or extra watcher. On completion, retrieve the result
and continue to step 6 only when required reviewer descendants have finished.

For a local file-report worker without completion events, arm a shell-condition
watch **after** stale results were cleared and launch was confirmed. Require a
nonempty `$RESULT` from this run whose `head_sha` matches `$HEAD` (or a fresh
`status: skipped` result). In pi use `until action=start`, a two-hour timeout,
and a label/context reference identifying this skill and the run. Do not use
absence of a process or idle status as proof of completion. On timeout, inspect
the worker and report the blocker rather than treating it as a review result.
Other harnesses use their supported background notification mechanism; if none
exists, disclose that limitation rather than blocking in a polling loop.

Record URL, HEAD, RESULT, worker reference, rounds left, push mode, and pinned
Pi staffing `openai/gpt-6.1-sol:high` in the run context. Report the worker link/reference
and any watcher id, then return control to the user. Persist consumed results before another
round; never rearm for an already handled result.

### 6. On wake

Read `fix-phase.md` in this skill's directory and follow it.
