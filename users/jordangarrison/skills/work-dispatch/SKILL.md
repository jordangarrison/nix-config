---
name: work-dispatch
description: Choose how to place dedicated tickets, threads, workspaces, and multi-repo workstreams in the current orchestration surface. Use when dispatching independent work or when a workflow needs workers; distinguish dedicated workstreams from native harness helpers. Cross-runtime handoffs require approval.
---

# Work dispatch

Shared dispatch policy, not a new orchestration engine. Use the runtime's tools
and instructions for mechanics. Ordinary delegation does not make the caller
coordinator-only; [[orchestrate]] is the explicit mode for that role.

## 1. Choose the work shape

- **Here:** work that belongs in this conversation. Routing to a repo alone
  does not require delegation.
- **Internal helper:** bounded research, review, exploration, or implementation
  assistance. Use native harness subagents under their tool rules. They need
  not become separate user-managed threads.
- **Dedicated workstream:** work with its own ongoing conversation, scope, or
  lifecycle. Give it an accessible thread/workspace in the owning surface.
  An explicit request for a ticket subthread chooses this shape. Another repo
  is evidence, not an automatic trigger: a lookup can be a helper; coordinated
  implementation may need its own workstream.

Choose based on independent ownership, not size alone. Ask when the choice
materially changes how the user will manage the work. A worktree isolates
files; a thread provides a conversation. Choose each separately.

## 2. Establish the owner

Honor an explicit user choice; otherwise retain the surface where the run
started. Use the current session's tool instructions and context as evidence.
An inherited environment variable or an installed CLI does not override that
owner. If ambiguous, ask rather than picking the first available backend.

Record the owner in the brief and any workflow ledger. Descendants inherit it.
Dedicated workers must be reachable and steerable through that surface's
supported controls. Do not promise tool, artifact, or context inheritance:
verify required capabilities and pass needed context explicitly.

If a capability is missing, describe the limitation and propose a remedy.
Cross-runtime handoffs require approval before launch, including where the
user will steer that work. `--yolo` skips ordinary staffing confirmations,
not this boundary; proceed only if the user explicitly preauthorized that
fallback. Missing required capabilities remain blockers.

## 3. Dispatch through the selected surface

- **T3 Code:** read [t3.md](t3.md). Follow the provided T3 tool rules for
  delegation versus new top-level threads and managed isolation.
- **Herdr:** load [[herdr-dispatch]] for dedicated workspaces and [[herdr]]
  for CLI mechanics. Herdr must be the selected owner, not just the terminal
  enclosing another orchestration surface.
- **Standalone harness:** use its supported delegation and isolation tools.
  A helper is not necessarily an independently steerable thread. If dedicated
  placement is unsupported, offer to work here or ask about another surface.

Discover supported models/settings from the selected runtime; honor explicit
choices and report unavailable ones. Native inheritance is acceptable when
supported and no workflow requests different staffing. Follow repo rules for
branch bases, environment preparation, validation, and commits.

A brief carries: objective, repo and ticket, scope, decisions already made,
acceptance criteria, owner, parent reference, and how to return results.
Provide absolute paths only when the worker can access them; otherwise send
content or supported artifacts. Record returned worker references, links,
checkout/base, and staffing. Report how the user can reach dedicated workers.

Done when launch is confirmed and the parent has a supported way to receive
results—not merely when a pane or checkout exists.

## 4. Coordinate and finish

The parent retains responsibility for results and dependencies unless the user
explicitly requests a handoff. Respect direct user steering in worker threads:
read current outcomes and decisions before integrating, rather than enforcing
an obsolete brief.

Nested delegation is allowed when the harness and task permit it. Workers may
use helpers or create dedicated workstreams, preserving the owner and passing
context onward. Avoid duplicate work and overlapping writes; no policy depth
cap is imposed here. Tool-enforced restrictions still apply.

Use native completion events and lifecycle controls. Do not add polling where
the runtime forbids it. For file-based completion, use fresh run-specific
positive evidence; record consumed results before rearming a watch. An idle
agent is not proof that its descendants have finished.

Integrate serially where changes overlap. Report results, validation, changed
decisions, and remaining blockers. Clean up only resources this run owns,
through the owning runtime, preserving dirty/unpushed work and useful threads
unless cleanup was authorized.
