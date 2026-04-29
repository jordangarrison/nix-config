# VTerm Agent Sessions Design

## Purpose

Move the primary Emacs agent workflow from `agent-shell` to workspace-aware agents running inside `vterm`, while leaving `agent-shell` installed and configured for optional use. The first version supports tool-named agents (`claude`, `codex`, `pi`) and is structured so future role/profile agents such as `codex-reviewer` or `pi-implementer` can fit naturally.

## Goals

- Replace the current `SPC j a c`, `SPC j a p`, and `SPC j a x` bindings with vterm-backed agent sessions.
- Replace the existing generic `SPC j a t` region-to-vterm behavior with agent-aware region sending.
- Preserve the session-management conventions built for `agent-shell`: workspace/project context, live session switching, and meaningful session labels.
- Send selected code with enough context for an agent to understand where it came from: project root, path, selected line numbers, and content.
- Paste prompts into vterm without submitting them so the prompt can be edited before sending.

## Non-goals

- Remove `agent-shell`, ACP adapter packages, or existing `agent-shell` configuration.
- Recreate `agent-shell` UI features such as tool-call rendering, collapsed tool summaries, or ACP-specific state.
- Build the full future profile registry in the first implementation.
- Automatically submit region sends by default.

## Existing State

The Doom config currently has:

- `agent-shell`, `acp`, and `shell-maker` declared in `packages.el`.
- `agent-shell` configuration for Claude and Codex in `config.org`.
- Pi disabled in `agent-shell` because streaming through `agent-shell` can freeze Emacs.
- Session-management helpers for `agent-shell` that capture workspace, project root, and default directory.
- A simple `VTerm Integration` section that sends a region to a literal `*vterm*` buffer through `SPC j a t`.

The new work should replace the generic vterm sender and the primary agent launch bindings, not delete the `agent-shell` package or configuration.

## Architecture

Add a new Doom config section for vterm agent sessions, implemented as a small `jag/agent-vterm-*` layer parallel to the existing `jag/agent-shell-*` helpers.

Each vterm agent session buffer records local metadata:

- `jag/agent-vterm-agent-name`
- `jag/agent-vterm-command`
- `jag/agent-vterm-launch-workspace-name`
- `jag/agent-vterm-launch-project-root`
- `jag/agent-vterm-launch-default-directory`
- `jag/agent-vterm-scope`, initially `workspace`

The first version defines built-in tool agents:

| Agent | Command |
| --- | --- |
| `claude` | `claude --dangerously-skip-permissions` |
| `codex` | `codex --yolo` |
| `pi` | `pi` |

These should be represented with a small internal registry-like data structure so later profile agents can extend the same shape with names such as `codex-reviewer` or `pi-implementer`.

## Session Scope and Naming

Default sessions are workspace-local. Starting Claude in the `nix-config` workspace creates a new buffer like:

```text
*agent:nix-config:claude*
```

Starting Claude again in the same workspace creates another distinct session with Emacs' normal generated suffix, such as `*agent:nix-config:claude*<2>`. Starting Claude in another workspace creates a distinct session for that workspace. Switching is handled explicitly through the live-session selectors, which keeps concurrent agents organized as more sessions accumulate.

If no Doom workspace name is available, the fallback session label should still be stable and readable, using project name or a generic workspace marker.

## Session Lifecycle

The replacement bindings are start-new-session commands:

- `SPC j a c` starts a new Claude vterm session in the current workspace.
- `SPC j a x` starts a new Codex vterm session in the current workspace.
- `SPC j a p` starts a new Pi vterm session in the current workspace.

Starting a session should:

1. Capture the current Doom workspace name.
2. Capture the current project root when available.
3. Capture the current `default-directory`.
4. Create a vterm buffer with a readable, unique session name.
5. Start the agent command in that vterm.
6. Store the metadata as buffer-local variables.
7. Ensure the buffer participates naturally in Doom workspace switching where possible.

Switching should only happen through the live-session selectors, not through the agent launch bindings.

## Session Selection

Add vterm equivalents of the existing active-session selectors:

- Switch to any live vterm agent session.
- Switch to a live vterm agent session in the current project.
- Switch to a live vterm agent session in the current Doom workspace.

Candidates should show at least workspace, project, agent name, and buffer name. Labels should remain useful when multiple sessions share an agent name.

## Region Send Behavior

Replace the current generic `SPC j a t` binding with an agent-aware sender.

`SPC j a t` should:

1. Require an active region.
2. Select a target vterm agent session:
   - If exactly one live agent session exists in the current workspace, use it.
   - If multiple live agent sessions exist in the current workspace, prompt with completion.
   - If no live agent session exists in the current workspace, prompt for an agent to start, then paste into it.
3. Build a context-rich prompt based on the target session metadata.
4. Paste the prompt into the target vterm.
5. Focus the target vterm.
6. Not send Enter; the user edits or submits manually.

A separate unbound helper may submit automatically after pasting, but the default binding must leave the prompt editable.

## Prompt Format

When the selected file is inside the target session's project root, use a project-relative path and include the project root header:

```text
Project root: /home/jordangarrison/dev/jordangarrison/nix-config
File: users/jordangarrison/tools/doom.d/config.org
Lines: 1012-1025

Content:
<selected text>
```

When the selected file is outside the target session's project root, keep the target project root header but use an absolute file path:

```text
Project root: /home/jordangarrison/dev/jordangarrison/nix-config
File: /absolute/path/outside/root/example.txt
Lines: 12-20

Content:
<selected text>
```

If the target session has no known project root, omit the project-relative behavior and use an absolute file path. Line numbers should reflect the selected region in the source buffer.

## Keybindings

Initial binding changes:

| Binding | New behavior |
| --- | --- |
| `SPC j a c` | Start a new workspace-local Claude vterm agent |
| `SPC j a x` | Start a new workspace-local Codex vterm agent |
| `SPC j a p` | Start a new workspace-local Pi vterm agent |
| `SPC j a t` | Paste selected region with context into a target vterm agent, without submitting |

Existing `agent-shell` bindings that do not conflict may remain for now. The old generic region-to-`*vterm*` helper should be removed or replaced so `SPC j a t` is no longer ambiguous.

## Error Handling

- If the requested CLI executable is missing, show a clear `user-error` naming the missing command.
- If no region is active for `SPC j a t`, show a clear `user-error`.
- If a recorded session buffer is dead, ignore it in selectors.
- If project root detection fails, use `default-directory` for session launch context and absolute file paths for sends.
- If a target vterm process is no longer live, either start a new session or report that the session must be restarted.

## Testing and Verification

Use the repo's Doom Emacs guidance for verification:

1. Validate pure helper functions with targeted Emacs evaluation where practical.
2. Validate integration with the running Emacs server via `emacsclient --eval`, not only `emacs --batch -Q`.
3. Confirm the new functions are defined after loading the config.
4. Confirm the replacement keybindings resolve to vterm-agent commands.
5. Manually verify, or provide eval checks for, these flows:
   - `SPC j a c` creates a new workspace-local Claude session each time.
   - `SPC j a x` creates a new workspace-local Codex session each time.
   - `SPC j a p` creates a new workspace-local Pi session each time.
   - `SPC j a t` formats a region with project root, file, lines, and content, then pastes without submitting.

Run `doom sync` only if package declarations or generated config require it. Since this design does not add packages, implementation should not require `doom sync` unless later changes alter package declarations.

## Future Extension: Agent Profiles

The first implementation should keep tool agents simple, but the internal data shape should support future profiles. A future profile might include:

- profile name, such as `codex-reviewer`
- base command, such as `codex --yolo`
- role label, such as `reviewer`
- default prompt prefix or instructions
- scope, such as workspace or global

This lets the workflow grow from tool-named sessions to role-aware sessions without replacing the session-management layer.
