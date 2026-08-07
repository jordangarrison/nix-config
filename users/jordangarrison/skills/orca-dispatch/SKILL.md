---
name: orca-dispatch
description: Dispatch a bounded repository task as a full ownership handoff to an agent in a fresh Orca-managed worktree. Use for `/orca-dispatch`, "dispatch this with Orca", "spin up an Orca worktree for X", "hand this to another Orca agent", or workspace instructions that route isolated work to Orca. Create the worktree from the repository's default base unless the user explicitly requests stacked work, deliver minimal context, report the new worktree and terminal, then stop. Use Orca orchestration instead when the user asks to supervise, coordinate, monitor, or wait for results.
---

# Orca Dispatch

Transfer one unit of repository work to an agent in a new Orca worktree without moving the current session or the user's focus away from its own task.

**Do not implement or monitor the dispatched task.** Create the isolated checkout, deliver the prompt, report the destination, and stand down. Do not create Orca orchestration Runs, Tasks, Dispatches, or lifecycle messages for this full handoff.

## Inputs

- **Task** (required): define the bounded outcome the receiving agent owns. A ticket identifier or URL may supply part of the task.
- **Repository**: use an explicit repository when given; otherwise resolve it from the current Orca context, the current checkout, or workspace routing instructions. Ask only when multiple repositories are genuinely plausible.
- **Agent**: default to the dispatcher's own supported agent kind (`codex` from Codex, `claude` from Claude, and so on). Honor an explicit agent request.
- **Worktree name**: use a short lowercase slug. Include the ticket identifier when relevant, for example `sre-123-fix-pool-leak`.
- **Lineage and base**: default to an independent top-level Orca worktree based on the repository's configured default base. Use child lineage and the current branch only when the user explicitly requests stacked or current-branch work.

## Workflow

1. **Load current Orca mechanics.** Load the `orca-cli` skill, resolve the session's Orca executable once, and read its version-matched guide with `ORCA skills get orca-cli`. Treat `ORCA` as a documentation placeholder and substitute the resolved executable in every command. Do not guess flags from this skill when the installed guide differs.
2. **Confirm Orca is available.** Run `ORCA status --json`; use `ORCA open --json` only when the guide says the runtime is not running. Prefer JSON for every agent-driven call.
3. **Resolve the repository.** Use `worktree current`, `repo list`, and `repo show` as needed. Register an explicitly selected local repository with `repo add --path <absolute-repo>` only when it is not already known to Orca. Use the exact returned repository selector.
4. **Check task independence.** Inspect the current checkout for uncommitted state. A fresh worktree does not contain uncommitted files. If the task depends on them, stop and explain the conflict; do not silently copy changes or commit them. Offer a current-worktree agent only if the user is willing to give up isolation.
5. **Choose lineage separately from the Git base.** For normal independent work, pass `--no-parent` and omit `--base-branch` so Orca uses the repository default. For explicitly stacked work, discover the exact current branch, use the guide's child-lineage selector, and pass that branch as the base. Never infer stacked work merely because dispatch starts inside a feature branch.
6. **Build a minimal handoff prompt.** Include the task, ticket, `Read AGENTS.md first`, and only context the receiver cannot cheaply rediscover: decisions already made, current-branch context, known gotchas, or relevant files. State that the receiving agent owns implementation and verification in its new worktree. Do not include orchestration lifecycle instructions.
7. **Create agent-first.** Follow the installed guide's full-handoff command. With the current command surface, the normal shape is:

   ```text
   ORCA worktree create --repo <repo-selector> --name <task-name> \
     --no-parent --agent <agent-kind> --prompt "<task brief>" \
     --setup run --json
   ```

   Add a supported ticket flag such as `--linear-issue <identifier-or-url>` when applicable. Prefer agent-first creation: do not create a second agent terminal after `--agent` already launched one. Let Orca place setup and configured default terminals.
8. **Read the receipt.** Copy `result.worktree.id`, including both repository ID and worktree path, and `result.agentTerminalHandle`; fall back to `result.startupTerminal.handle` only for an older runtime. Never shorten the worktree ID or predict handles. Verify only that creation and initial prompt delivery succeeded. If delivery is explicitly unconfirmed, use the single returned agent handle and the guide's readiness/send flow once; do not duplicate the prompt.
9. **Report and stop.** Report the worktree name, complete ID or checkout path, agent kind, and terminal handle. Do not activate the worktree, read the worker terminal, wait for completion, or continue the implementation unless the user later asks for supervised coordination.

Repeat the workflow once per repository for a multi-repository handoff, giving each agent only its repository's slice of the task.

## Special cases

- **Custom agent model or arguments:** follow the version-matched `orca-cli` full-handoff recipe. The built-in `--agent` launcher may not accept provider-specific arguments. Use the documented two-step worktree and terminal flow only when required, wait only long enough to avoid losing the initial prompt, and then stop.
- **No owning Git repository:** do not create a fake repository merely to obtain an Orca worktree. Use the workspace's investigation convention or ask the user to select an owning repository.
- **Supervision requested:** switch to the `orchestration` skill when the user asks to supervise, coordinate a DAG, wait for completion, track results, or handle ask/reply. Do not partially mix that lifecycle with this handoff.

## Cleanup

Clean up only on a later explicit request. Re-resolve the exact worktree, inspect it for dirty state, and use the installed guide's `worktree rm` command. Use `--force` only after the user confirms deletion of dirty work, and remove only worktrees created by this dispatch unless broader cleanup was requested.
