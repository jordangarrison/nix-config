# Agent Shell ACP Adapters Design

## Summary

Add Xenodium's `agent-shell` to Jordan's Doom Emacs configuration with support for Claude, Codex, and Pi through the Agent Client Protocol (ACP). Keep Emacs UI configuration in Doom, and manage ACP adapter binaries declaratively through Home Manager/Nix so they are reusable by other ACP clients later.

## Goals

- Install and configure `agent-shell` for Doom Emacs.
- Expose Claude, Codex, and Pi as available `agent-shell` agents.
- Manage ACP adapter binaries declaratively with Home Manager, not ad-hoc global npm installs.
- Make the adapter setup reusable outside Emacs.
- Preserve the existing AI/LLM setup, including `gptel`, `claude-code-ide`, and vterm helpers.

## Non-goals

- Replace `claude-code-ide`, `gptel`, or existing terminal-agent workflows.
- Configure every agent supported by `agent-shell`.
- Add API-key management or new secret storage flows.
- Change existing Pi, Claude, Codex, or OpenCode package installation unless required for ACP support.

## Current context

The Doom config lives in `users/jordangarrison/tools/doom.d/`:

- `init.el` already enables `vterm` and Doom's `:tools llm` module.
- `packages.el` already declares custom packages such as `claude-code-ide`.
- `config.org` has an `AI/LLM Integration` section with `gptel`, vterm helpers, ChatGPT, and Claude Code IDE configuration.

Home Manager configuration lives in `users/jordangarrison/home.nix`:

- `home.packages` already installs `pkgs.llm-agents.pi`, `pkgs.llm-agents.claude-code`, `pkgs.llm-agents.codex`, and `pkgs.llm-agents.opencode`.
- `programs.emacs` is enabled and evaluates to Emacs 30.2 on the checked configuration, satisfying `agent-shell`'s Emacs 29.1+ requirement.

`agent-shell` requires external ACP adapter commands. The desired supported commands are:

- `claude-agent-acp` or compatible Claude ACP adapter.
- `codex-acp`.
- `pi-acp`.

## Considered approaches

### Approach 1: Doom-only integration

Add `agent-shell`, `acp`, and `shell-maker` to Doom and leave all ACP adapters as manual `npm -g` or user-managed commands.

Pros:

- Smallest code change.
- Fastest experiment.

Cons:

- Not reproducible.
- Emacs daemon PATH issues are more likely.
- Does not match this repository's declarative Nix style.

### Approach 2: Put ACP adapters directly in the Emacs configuration

Configure adapter installation or path management near the Doom setup.

Pros:

- Keeps all `agent-shell`-related work in one visible area.
- Simple mental model if adapters are treated as Emacs-only dependencies.

Cons:

- ACP adapters are external runtime tools, not Emacs Lisp packages.
- Makes reuse by other ACP clients harder.
- Mixes UI configuration and system package management.

### Approach 3: Reusable Home Manager ACP adapters module

Create a Home Manager module for ACP adapter binaries, import it in Jordan's home configuration, and keep Doom responsible only for `agent-shell` behavior.

Pros:

- Declarative and reproducible.
- Separates runtime dependencies from Emacs UI configuration.
- Reusable by future ACP clients or non-Emacs workflows.
- Fits existing module patterns in `modules/home/`.

Cons:

- Slightly more initial structure than a one-off package list.
- May require packaging `pi-acp` if no existing Nix package is available.

## Decision

Use Approach 3.

Create a reusable module at `modules/home/acp-adapters/default.nix` and import it from `users/jordangarrison/home.nix`. The module owns external ACP adapter binaries. Doom owns `agent-shell` packages, commands, and keybindings.

## Home Manager module design

Add a Home Manager module with options under `programs.acp-adapters`:

```nix
programs.acp-adapters = {
  enable = true;

  claude.enable = true;
  codex.enable = true;
  pi.enable = true;
};
```

The module should:

- Add enabled adapter packages to `home.packages`.
- Default each adapter to enabled when `programs.acp-adapters.enable = true`, unless that is awkward in Nix option semantics; otherwise explicitly enable all three from `home.nix`.
- Prefer packages from the `pkgs.llm-agents` flake overlay for ACP adapters.
- Keep package selection overridable per adapter, for example `programs.acp-adapters.claude.package`, so callers can swap in nixpkgs, local packages, or future upstream packages without changing the module.
- Keep the public interface generic enough for later adapters.

Expected package mapping:

- Claude: default to `pkgs.llm-agents.claude-code-acp`, whose main program is `claude-agent-acp`.
- Codex: default to `pkgs.llm-agents.codex-acp`, whose main program is `codex-acp`.
- Pi: default to `pkgs.llm-agents.pi-acp` when that package exists. The current checked `llm-agents` input does not expose `pi-acp`, so the module must make this package choice overridable and fail clearly if Pi support is enabled without an available Pi ACP package.

## Doom Emacs design

Update `users/jordangarrison/tools/doom.d/packages.el`:

```elisp
(package! shell-maker)
(package! acp)
(package! agent-shell)
```

Update `users/jordangarrison/tools/doom.d/config.org` under `AI/LLM Integration` with a new `Agent Shell` subsection.

The configuration should:

- Require `acp` and `agent-shell` before configuration, per `agent-shell`'s Doom instructions.
- Limit `agent-shell-agent-configs` to Claude, Codex, and Pi.
- Configure command names explicitly:
  - `agent-shell-anthropic-claude-acp-command` -> `("claude-agent-acp")` or the actual installed Claude ACP command.
  - `agent-shell-openai-codex-acp-command` -> `("codex-acp")`.
  - `agent-shell-pi-acp-command` -> `("pi-acp")`.
- Inherit the Emacs process environment for spawned agents where supported, so agent commands see expected `PATH`, `HOME`, auth files, and Nix-managed binaries.
- Use login-based auth for Claude and Codex by default, matching existing CLI subscription/login workflows.
- Leave Pi auth to Pi's existing login/configuration behavior.

Suggested keybindings under the existing personal AI namespace:

```elisp
(map! :leader :desc "Agent shell" "j a a" #'agent-shell)
(map! :leader :desc "Agent shell Claude" "j a c" #'agent-shell-anthropic-start-claude-code)
(map! :leader :desc "Agent shell Codex" "j a x" #'agent-shell-openai-start-codex)
(map! :leader :desc "Agent shell Pi" "j a p" #'agent-shell-pi-start-agent)
```

This keeps the existing `j a t` vterm helper intact.

## Data and state

`agent-shell` may create `.agent-shell/` directories under project roots for transcripts and related state. The default behavior adds `.agent-shell/` to a project's `.gitignore` when needed.

For the first implementation, keep this default behavior. If project-tree transcript storage becomes noisy later, configure `agent-shell-dot-subdir-function` to store data under `user-emacs-directory` instead.

## Verification plan

After implementation:

1. Run Doom sync:
   ```bash
   doom sync
   ```
2. Verify adapter commands exist:
   ```bash
   command -v claude-agent-acp || command -v claude-code-acp
   command -v codex-acp
   command -v pi-acp
   ```
3. Build or switch Home Manager through the repo's normal flow, using `--no-nom` for `nh` commands:
   ```bash
   nh home build . --no-nom
   ```
   or the appropriate NixOS build/test command for the active host.
4. Start Emacs and verify these commands are available:
   - `M-x agent-shell`
   - `M-x agent-shell-anthropic-start-claude-code`
   - `M-x agent-shell-openai-start-codex`
   - `M-x agent-shell-pi-start-agent`
5. Start at least one shell and confirm the adapter launches without a missing-command error.

## Risks and mitigations

- **Adapter command name mismatch:** Verify package outputs and configure Doom to use the actual command name or provide a wrapper.
- **Pi adapter not exposed by `pkgs.llm-agents`:** Keep the Pi package option overridable and fail clearly when Pi support is enabled without a package. Add or override a Pi ACP package later once it is available from the llm flake or a local package.
- **Emacs daemon environment mismatch:** Prefer Nix-managed binaries in user profile and configure environment inheritance for agent processes.
- **`agent-shell` package/API churn:** Keep configuration minimal and avoid relying on experimental features beyond supported agent configs and command variables.
- **Overlapping AI tools:** Keep existing `claude-code-ide`, `gptel`, and vterm workflows; `agent-shell` is additive.

## Open follow-up decisions

- Add Pi ACP support once `pkgs.llm-agents.pi-acp` exists, or set `programs.acp-adapters.pi.package` to an explicit override.
- Decide later whether `agent-shell` transcripts should stay in project `.agent-shell/` directories or move under Emacs state.
