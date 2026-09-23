# Skill authoring conventions

Rules for every skill in this directory. They apply when creating a new skill and when modifying an existing one.

## `--yolo` — universal skip-interactivity flag

Every skill that has interactive gates (previews-for-approval, y/n confirmations, per-item sign-offs, "include X?" prompts) supports `--yolo`. It means: skip all interactivity and proceed autonomously.

- **Authoring:** if the skill you're writing or editing has any interactive gate, document `--yolo` in its SKILL.md. If it already has a skill-specific skip flag (e.g. multi-agent-pr-review's `--skip-user-confirmation`), make `--yolo` an alias for it rather than a second mechanism.
- **Invocation:** treat `--yolo` as valid on any skill here even if its SKILL.md predates this rule and doesn't mention it.
- **What `--yolo` does NOT waive:** still show/report what was done so the user can audit it (autonomy is not silence); still stop on genuine blockers (missing inputs, ambiguous state), destructive actions outside the skill's documented scope, and never-rules like force-push.

## Other conventions

- Skills here are fanned out to claude/codex/pi/opencode via `programs.agent-skills` (out-of-store symlinks — edits are live without a rebuild, but new skill directories need `git add` + rebuild).
- Upstream skills are declared in `programs.agent-skills.external` in `users/jordangarrison/home.nix`. For a skill that documents a CLI, take it from that CLI's package so the versions match. For any other skill, add a `flake = false` input. Never install skills with `npx skills`, `pup skills install`, `readwise skills install`, `flo skills add`, or by copying files by hand. If such a directory takes a declared name, the next switch moves it aside to `<name>.backup`, and agents then load it as a stale duplicate skill. A conflicting symlink, or a conflict on standalone Home Manager without `-b`, fails the switch instead.
- Interactive gates should be the exception, not the default: prefer "invoking the skill is the consent" with an audit-trail preview over y/n confirmation gates. Reserve hard stops for genuine anomalies (see sre-review-worktrees' Red Flags for the pattern).
