# Agent Shell Active Session Management Design

## Context

Doom Emacs is configured with Vertico for minibuffer completion, Projectile for project detection, and Doom workspaces backed by `persp-mode`. `agent-shell` already has ACP historical session selection, but this work targets live active `agent-shell` buffers.

Today, active agent sessions can exist globally but be hard to reach from normal Doom workflows. In particular, `SPC b b` uses Doom's workspace-aware Vertico/Consult buffer switcher, so buffers created by `agent-shell` in background/no-focus paths may not appear if they were never added to the launching workspace.

## Goals

1. Make newly launched `agent-shell` buffers visible in the Doom workspace where they were launched.
2. Add Vertico-backed selectors for active agent sessions.
3. Support both global and scoped active-session selection.
4. Keep the design compatible with future workflows where one Doom workspace may represent a folder of related worktrees.

## Non-goals

- Do not change ACP historical session listing or resume semantics.
- Do not persist custom session metadata outside the live Emacs process.
- Do not replace Doom's normal buffer switching UI.

## Approach

Use live buffers as the source of truth for active sessions. When an `agent-shell` buffer is created, explicitly attach it to the current Doom workspace and store lightweight buffer-local launch metadata.

The implementation should advise the central `agent-shell--start` path because all standard agent launch commands eventually create buffers through it. The advice will capture the launching workspace, project root, and default directory before `agent-shell--start` runs, then apply metadata and workspace membership to the returned buffer.

## Buffer metadata

Each new `agent-shell` buffer should store:

- `jag/agent-shell-launch-workspace-name`: the Doom workspace name active at launch time.
- `jag/agent-shell-launch-project-root`: the normalized project root active at launch time.
- `jag/agent-shell-launch-default-directory`: the normalized `default-directory` active at launch time.

Project root should prefer Doom/Projectile project detection via `doom-project-root` where available, and fall back to `agent-shell-cwd` or `default-directory` as needed.

## Workspace registration

When Doom workspaces and `persp-mode` are active, the new shell buffer should be added to the launching workspace using `persp-add-buffer`. This makes active agent sessions discoverable through Doom's standard workspace buffer selector (`SPC b b`).

If the workspace no longer exists or workspaces are disabled, the registration step should safely do nothing.

## Active session selectors

Add three commands backed by `completing-read`, so Vertico provides the UI:

1. `jag/agent-shell-switch-session`
   - Shows all live `agent-shell` buffers globally.

2. `jag/agent-shell-switch-project-session`
   - Shows live `agent-shell` buffers whose launch project root matches the current project root.
   - This is best for selecting sessions tied to the current repo or worktree.

3. `jag/agent-shell-switch-workspace-session`
   - Shows live `agent-shell` buffers attached to the current Doom workspace or launched from it.
   - This is best for task-oriented workspaces, including future workspaces spanning a folder of related worktrees.

Each selector should display useful candidate labels including agent name, project/workspace context, session id when available, and buffer name. The selected candidate should switch to the underlying buffer via `agent-shell--display-buffer` when available, otherwise `switch-to-buffer`.

## Keybindings

Add the selectors under the existing `SPC j a` prefix:

- `SPC j a s`: switch active session globally.
- `SPC j a S`: switch active session in current project.
- `SPC j a w`: switch active session in current workspace.

Existing bindings remain unchanged.

## Error handling

- If no active sessions exist for a selector, raise a clear `user-error`.
- If workspace/project metadata is missing on older buffers, fall back to current `agent-shell` helpers where possible.
- If duplicate display labels occur, include buffer names and keep an internal label-to-buffer mapping so selection remains deterministic.

## Testing and verification

Validate pure helper functions with targeted evaluation where practical. Validate Doom and `agent-shell` integration in the running Emacs server with `emacsclient --eval`, per `users/jordangarrison/tools/doom.d/AGENTS.md`.

Verification should cover:

1. New agent buffers receive launch metadata.
2. New agent buffers are added to the launching Doom workspace.
3. Global selector sees all live agent-shell buffers.
4. Project selector filters by current project root.
5. Workspace selector filters by current Doom workspace.
6. `SPC b b` can see newly launched agent-shell buffers in the launching workspace.
