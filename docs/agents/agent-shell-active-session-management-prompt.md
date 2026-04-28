# Agent Shell Active Session Management Handoff Prompt

Use this prompt to start or resume the Doom Emacs `agent-shell` active session management work.

```markdown
We are working in `/home/jordangarrison/dev/jordangarrison/nix-config`.

Read first:
- `/home/jordangarrison/dev/jordangarrison/CLAUDE.md`
- `/home/jordangarrison/dev/jordangarrison/nix-config/AGENTS.md`
- `users/jordangarrison/tools/doom.d/AGENTS.md`
- `docs/superpowers/specs/2026-04-28-agent-shell-active-session-management-design.md`

Project/validation constraints:
- This is a Nix config repo. Use `nh` with `--no-nom` for all `nh` commands.
- For Doom/Emacs integration, prefer `emacsclient --eval` against the running Emacs server.
- Do not use batch Emacs as the primary signal for Doom/package integration.
- Avoid broad rewrites. Prefer narrow, reversible changes in `users/jordangarrison/tools/doom.d/config.org`.
- Report exact commands/evaluations and results.

Current context:
- Doom uses Vertico for minibuffer completion.
- Doom `:ui workspaces` is enabled and backed by `persp-mode`.
- Projectile is enabled; project roots should prefer `doom-project-root` where available.
- `agent-shell` is configured in `users/jordangarrison/tools/doom.d/config.org`.
- Agent Shell section starts around the `*** Agent Shell Configuration` heading.
- `agent-shell` upstream checkout is at `/home/jordangarrison/.emacs.d/.local/straight/repos/agent-shell`.
- Pi is temporarily disabled inside Emacs `agent-shell` because long streamed responses can freeze Emacs.
- `pi-acp` should remain installed/available outside Emacs. Do not remove it from Home Manager/Nix.
- Current Emacs `agent-shell-agent-configs` should contain Claude and Codex only until Pi streaming stability is addressed.

Existing design:
- Spec file: `docs/superpowers/specs/2026-04-28-agent-shell-active-session-management-design.md`
- Commit: `807aed3 docs(doom): design agent-shell active session management`

Goal:
Implement active session management for live `agent-shell` buffers using Doom workspaces, Projectile/project roots, and Vertico selectors.

Important product decisions already made:
1. Use live `agent-shell` buffers as the source of truth, not historical ACP sessions.
2. Attach newly-created `agent-shell` buffers to the Doom workspace where they were launched.
3. Store buffer-local launch metadata so selectors can filter by project/workspace even later.
4. Provide both project-root and workspace filters:
   - project root = repo/worktree scope
   - workspace = broader task context, possibly spanning multiple related worktrees
5. Keep normal Doom `SPC b b` useful by ensuring buffers are registered with the launching workspace.
6. Add dedicated agent-shell selectors for global/project/workspace active sessions.

Implementation target:
- File: `users/jordangarrison/tools/doom.d/config.org`
- Keep changes in/near the existing Agent Shell section unless a small helper section is clearly better.

Implementation details to design/execute:

1. Capture launch context around `agent-shell--start`
   - Advise the central start path rather than each individual agent command.
   - Before startup, capture:
     - current Doom workspace name
     - current project root via `doom-project-root` when available
     - current `default-directory`
   - After startup returns/creates the shell buffer, store metadata on that buffer.
   - If `agent-shell--start` does not return a buffer in the current upstream version, inspect the function and use the narrowest reliable hook/advice point.

2. Buffer-local metadata
   Add variables similar to:
   - `jag/agent-shell-launch-workspace-name`
   - `jag/agent-shell-launch-project-root`
   - `jag/agent-shell-launch-default-directory`

   Normalize paths with `file-truename`/`directory-file-name`/`file-name-as-directory` as appropriate so project comparisons are stable across symlinks.

3. Workspace registration
   - If Doom workspaces and `persp-mode` are active, add new shell buffers to the launching workspace with `persp-add-buffer`.
   - Do this defensively:
     - no error if workspaces are disabled
     - no error if the workspace no longer exists
     - no error if `persp-add-buffer` API differs; inspect local Doom/persp usage first

4. Active session discovery
   - Use live buffers where `(derived-mode-p 'agent-shell-mode)` is true.
   - Ignore dead buffers.
   - Prefer upstream helpers like `agent-shell-buffers` and `agent-shell-project-buffers` when they match the need, but live-buffer metadata is the source of truth for new filtering.

5. Vertico/completing-read selectors
   Add commands:
   - `jag/agent-shell-switch-session`
     - all live `agent-shell` buffers globally
   - `jag/agent-shell-switch-project-session`
     - live `agent-shell` buffers whose launch project root matches current project root
   - `jag/agent-shell-switch-workspace-session`
     - live `agent-shell` buffers attached to or launched from current Doom workspace

   Candidate labels should be useful and deterministic. Include enough context to distinguish duplicate sessions, such as:
   - agent identifier/name when available
   - buffer name
   - launch project basename/root
   - launch workspace
   - ACP session id when available

   Use an internal candidate-to-buffer mapping so duplicate labels do not switch to the wrong buffer.

6. Buffer switching behavior
   - Prefer `agent-shell--display-buffer` if available and appropriate.
   - Fallback to `switch-to-buffer`.
   - Do not replace normal Doom buffer switching.

7. Keybindings
   Add under existing `SPC j a` prefix:
   - `SPC j a s`: global active session selector
   - `SPC j a S`: current project active session selector
   - `SPC j a w`: current workspace active session selector

   Keep existing bindings intact:
   - `SPC j a a`: `agent-shell`
   - `SPC j a c`: Claude
   - `SPC j a e`: compose prompt bottom window
   - `SPC j a p`: currently disabled Pi message
   - `SPC j a q`: queue request
   - `SPC j a x`: Codex

8. Error handling
   - If no active sessions match, raise a clear `user-error`.
   - If metadata is missing on older buffers, fall back where possible:
     - buffer `default-directory`
     - current `agent-shell` project helpers
     - workspace buffer membership
   - Selectors should not error just because a buffer lacks complete metadata.

Validation expectations:
Use `emacsclient --eval` after tangling/reloading config.

Suggested checks:

1. Emacs server and agent-shell loaded:
```bash
emacsclient --eval '(list :ok t :pid (emacs-pid) :agent-shell-loaded (featurep '\''agent-shell))'
```

2. New helper functions are defined:
```bash
emacsclient --eval '(list :global (fboundp '\''jag/agent-shell-switch-session) :project (fboundp '\''jag/agent-shell-switch-project-session) :workspace (fboundp '\''jag/agent-shell-switch-workspace-session))'
```

3. Pi remains disabled in Emacs but available outside:
```bash
emacsclient --eval '(progn (require '\''agent-shell) (mapcar (lambda (cfg) (map-elt cfg :identifier)) agent-shell-agent-configs))'
command -v pi-acp
```

4. Keybindings exist:
```bash
emacsclient --eval '(let ((m doom-leader-map)) (list :s (lookup-key m (kbd "j a s")) :S (lookup-key m (kbd "j a S")) :w (lookup-key m (kbd "j a w")) :p (lookup-key m (kbd "j a p"))))'
```

5. Launch Claude/Codex from a workspace/project and verify:
   - buffer receives launch metadata
   - buffer is present in the launching workspace
   - global selector sees it
   - project selector sees it from the same project
   - workspace selector sees it from the same workspace
   - `SPC b b` can see it in the launching workspace

If Nix files are not changed, do not run `nh` unnecessarily.
If package declarations are not changed, `doom sync` may not be needed, but `config.org` changes must be tangled/reloaded via the normal Doom workflow.

Deliverables:
- Implementation in `users/jordangarrison/tools/doom.d/config.org`.
- Fresh validation evidence from `emacsclient --eval`.
- Commit with a conventional message, for example:
  - `feat(doom): add active agent-shell session switching`
```
