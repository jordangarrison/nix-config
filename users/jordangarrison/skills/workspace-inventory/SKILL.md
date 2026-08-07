---
name: workspace-inventory
description: Generate or refresh a workspace folder's .workspace.json repo inventory — the routing table that the generic workspace router (AGENTS.md -> ROUTER.md) points agents at. Use when .workspace.json is missing, when a workspace router doc says it is stale, when repos have been added to or removed from a workspace folder like ~/dev/jordangarrison, ~/dev/flocasts, or ~/dev/kartingcoach, or when the user asks to reindex/re-inventory a workspace.
---

# Workspace inventory

Regenerates `<workspace>/.workspace.json`: one entry per git repo directly
under the workspace folder, with `name`, `description`, `language`,
`defaultBranch`, `remote`, and `hasAgentDoc`. The generic workspace router
(`AGENTS.md` in each workspace folder) uses this file as its routing table.

## Usage

```bash
bash <this skill dir>/generate.sh <workspace-dir>
# e.g.
bash <this skill dir>/generate.sh ~/dev/flocasts
```

The script is idempotent — it rewrites `.workspace.json` from current disk
state every run. Timestamps land in `generatedAt`.

## Notes

- Descriptions are extracted from each repo's own `CLAUDE.md` / `AGENTS.md` /
  `README.md` (first meaningful prose line). If a description is weak or
  empty, fix the *repo's* doc rather than hand-editing `.workspace.json` —
  hand edits are lost on the next regeneration.
- Only immediate subdirectories that are git repos (or worktree checkouts,
  which have a `.git` file) are included. `.worktrees/` and other dot-dirs
  are skipped automatically because they don't sit directly under the
  workspace as repo dirs.
- After regenerating, skim the output for repos with `hasAgentDoc: false`
  that see regular work — offering to `/init` a CLAUDE.md there is the
  router's convention.
