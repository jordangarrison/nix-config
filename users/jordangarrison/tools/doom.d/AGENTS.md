# AGENTS.md

Guidance for AI coding agents working in this Doom Emacs configuration.

## Testing Emacs Lisp Changes

Prefer validating Doom/Emacs configuration changes against the running Emacs server instead of extracting snippets with ad-hoc scripts or using `emacs --batch -Q` as the primary signal.

Use `emacsclient --eval` for checks that depend on the real loaded environment, package state, advice, Doom macros, or interactive behavior:

```bash
emacsclient --eval '(featurep '\''agent-shell)'
emacsclient --eval '(fboundp '\''jag/agent-shell-tool-call-expanded-by-default-p)'
```

For functions defined in `config.org`, ensure the running Emacs has the latest config loaded before evaluating behavior. If needed, tangle/sync/reload through the normal Doom workflow rather than manually extracting source blocks with Python or shell scripts.

Use batch Emacs only as a secondary or isolated check:

- `emacs --batch -Q` is acceptable for pure helper functions with no Doom/package dependencies.
- Do not treat `emacs --batch -Q` as sufficient for integration with Doom, `agent-shell`, advice, keybindings, or package-loaded behavior.
- Avoid Python-based extraction of Elisp from `config.org` unless explicitly needed for a one-off investigation; prefer Doom/Org tooling or the live Emacs server.

## Verification Expectations

When changing this directory:

1. Validate pure Elisp helpers with targeted evaluation or ERT when useful.
2. Validate Doom/package integration with `emacsclient --eval` in the running server.
3. Run `doom sync` only when package declarations or generated config require it.
4. Report the exact commands/evaluations used and their results.
