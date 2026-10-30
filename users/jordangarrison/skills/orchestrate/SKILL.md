---
name: orchestrate
description: Declare this session a coordinator-only orchestrator. Decompose work, dispatch through work-dispatch in the starting orchestration surface, track workers, and own integration decisions without implementing. Triggered by /orchestrate, "you are the orchestrator", or "hand this off, don't do it yourself". Supports --yolo for routine staffing gates, not cross-runtime handoffs.
---

# Orchestrate

An explicit role for this conversation, not the default consequence of
launching a worker. The orchestrator produces briefs, dispatches, a ledger,
and integration decisions. It does not implement, run workers' assigned tests,
or fix small findings itself. Read-only inspection and ledger writes are fine.

## 1. Intake and placement

Read [[work-dispatch]] and establish the owning surface. Fetch a named ticket
with available tracker tools, or ask for its text if unavailable. Break work
into independently owned tasks, sequencing overlapping writes. Keep the
concurrent set small enough to supervise; choose helpers versus dedicated
workstreams using work-dispatch, not an environment-variable gate.

Use supported staffing and honor explicit model/settings requests. Report the
choice. `--yolo` permits routine staffing choices without confirmation; a
cross-runtime handoff still needs explicit approval or a preauthorized fallback.
If dispatch is unavailable, surface the blocker rather than implementing here.

## 2. Ledger and briefs

Keep a run-specific ledger outside repositories under
`~/.local/state/orchestrate/<repo>/<ticket-or-slug>-<unique-run-id>/` (respect
`XDG_STATE_HOME`). Report the path. Resume only an identified existing run;
inspect its records before dispatching to avoid duplicate workers.

Record in `ledger.md`: objective, owner, parent reference, task scopes,
dependencies, status, user decisions, and integration results. Status values:
`pending | dispatched | blocked | done | done-with-concerns | failed`.
Record dispatch references, links, checkout/base, staffing, and completion
mechanism in `dispatch.jsonl`. These records point to runtime state; they do
not replace native lifecycle tools.

Write a self-contained `task-N-brief.md` with:

- Objective, repo/ticket, scope and non-goals.
- Acceptance criteria and checks.
- Owned files or coordination boundaries.
- Decisions already made and their reasons.
- Orchestration owner and parent reference.
- Report contract: status, changes/commits, tests, decisions changed by user
  steering, concerns, and any outstanding descendants.

Use accessible absolute paths or send the brief content through the runtime.
Workers may delegate further under work-dispatch and their harness rules.
Only label a worker coordinator-only if that role is appropriate; otherwise it
may implement as well as delegate.

## 3. Dispatch and supervise

Use [[work-dispatch]], which selects the runtime-specific mechanics. Confirm
launch and record returned references. Give the user links or workspace details
for dedicated workstreams. Keep coordinating unless explicitly handing off.

Use native completion events where provided. For Herdr file reports, require
fresh positive evidence from this run before waking; a worker's idle status
alone is not a completion signal. A shell-condition watch uses the harness's
watch facility rather than a blocking sleep loop. Persist consumed result IDs
before rearming. Do not add watches for T3 delegates that already notify.

Read current worker outcomes before acting, including user steering and live
descendants. Resolve routine choices within scope and log the ruling; bring
scope changes, missing permissions, and cross-runtime proposals to the user.
Use supported continuation controls or launch a new bounded assignment when
required by the runtime. Stop repeated failed attempts and report the blocker.

## 4. Integrate

Implementation can run in parallel; integration of overlapping changes is
serial. Inspect each report and diff, request review where useful, and dispatch
any fixes or integration edits. The coordinator does not edit repo files.

Push, PR, and merge only within the user's authorization and repository rules.
Record validation evidence and remaining concerns. Preserve independently
steerable work until cleanup is appropriate; use the owning runtime to clean
up only this run's resources, with clean/pushed work and required approval.

Finish with tasks, results, links, and open concerns. A task is not complete
while its required child work remains outstanding. On resume or compaction,
read the ledger and current runtime state before issuing further work.
