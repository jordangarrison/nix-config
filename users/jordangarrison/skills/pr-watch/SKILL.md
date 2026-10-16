---
name: pr-watch
description: >-
  Use to watch my own open PR while other people review it, and address their
  feedback as it arrives. Wakes on each new review or comment, verifies every
  finding, fixes or declines it, runs the repo's checks, pushes, replies on the
  comment, and re-requests review. Runs until the PR merges, closes, or is
  approved. Started by [[infra-reviews]] `post`; also directly. Its fix-and-reply
  procedure (`address.md`) is shared with [[self-review]]. Triggered by
  `/pr-watch`, "watch my PR", "address the review comments as they come in".
---

# PR Watch

Arm a watcher on my PR → wake on new feedback → address it in this session (`address.md`) → re-arm → stop when the PR is done.

This session is the **author**. For reviews from my own reviewer tab, use [[self-review]] instead; it has rounds, this does not — other people review on their own schedule.

## Inputs

| Input | Default |
|---|---|
| PR URL | `gh pr view --json url` in the current checkout |
| `--until merged\|approved` | `merged`. `approved`: stop once the PR is approved and nothing is unhandled. |
| `--for <duration>` | `24h`. Then report and stop; re-run to resume. |
| `--interval <duration>` | `2m` |
| `--on-stop <instruction>` | Run when the watch stops, before the report. Set by callers (e.g. [[infra-reviews]] marks the post merged). |
| `--yolo` | Post replies to other people without preview. |

Invoking the skill is the consent to fix, commit, and push to this PR's branch.

## Steps

### 1. Preflight

All must hold; stop and say which one failed otherwise.

- The PR resolves, is open, and its author is me (`gh api user -q .login`).
- The checkout is on the PR's head branch with a clean tree.
- The remote holds every local commit (`git status -sb` shows no `ahead`). If ahead: `--yolo` → push (normal push, never force); attended → ask to push.

### 2. State file

`~/.cache/pr-watch/<owner>-<repo>-<num>.json`, shared with [[self-review]] so neither re-addresses what the other handled. Reuse it when present; otherwise create:

```json
{
  "repo": "<owner>/<repo>", "num": 1097, "me": "<login>",
  "checkout": "<absolute path of this checkout>",
  "handled": []
}
```

Then set this watch's fields: `until`, `deadline` (ISO time), `yolo`, `on_stop`. On create, mark what is already answered: run `check.sh` (step 3) once and add each listed `comment:<id>` that already has a reply from me to `handled`. Everything else that exists now is open feedback, addressed on the first wake.

### 3. Arm the watcher

The gate is `check.sh` in this skill's directory (`~/.agents/skills/pr-watch/check.sh <state-file>`). It exits 0 when the PR is no longer open or has feedback not in `handled`, and prints which.

| Harness | Watcher |
|---|---|
| pi | `until` with `action: "start"`, `condition`: `<check.sh> <state-file>`, `intervalSeconds`: the interval, `timeoutSeconds`: seconds to `deadline`, `wake: "agent"`, `instruction`: "pr-watch woke for `<URL>`. Follow pr-watch SKILL.md step 4 with state file `<path>`." |
| Claude Code | `Bash` with `run_in_background: true`: `timeout <secs-to-deadline> sh -c 'until <check.sh> <state-file>; do sleep <interval-secs>; done'`. Its completion notification is the wake. |
| Other | Run the same loop in the foreground. |

Report: PR, state file, watcher id, stop condition. Then return control — this session keeps working until the wake.

### 4. On wake

Run `check.sh <state-file>` again (the wake may be stale). First match wins:

| Situation | Action |
|---|---|
| Past `deadline` | Stop (step 5). |
| `pr:MERGED` / `pr:CLOSED` | Stop (step 5). |
| `feedback:` + ids | Follow `address.md` in this skill's directory with those ids. Then: `until: approved` and `gh pr view --json reviewDecision` is `APPROVED` → stop; otherwise re-arm (step 3). If `address.md` stopped on a dirty checkout, stop without re-arming. |
| exit 1 (nothing new) | Re-arm (step 3). |

### 5. Stop and report

Run `on_stop`, if set. Keep the state file (a later `/pr-watch` resumes from it); delete it when the PR is merged or closed.

```
PR:        <URL>  (<open | merged | closed>, <reviewDecision>)
Addressed: <n> items — fixed <n> (<shas>), declined <n>, answered <n>
Declined:  <one line each>
Stopped:   <reason>
```
