---
name: self-review
description: >-
  Use to get a multi-agent review of my own open PR and have its findings fixed
  automatically. From the session that wrote the PR: opens a new herdr tab in
  the current workspace, starts an agent there that runs
  [[multi-agent-pr-review]] `--yolo` on the PR (posted as a COMMENT review),
  watches for the result, then fixes or declines every finding in this session
  with [[pr-watch]]'s shared procedure, pushes, and replies on each review
  comment; `--rounds` re-reviews after each push. For other people's reviews,
  use [[pr-watch]]. Triggered by `/self-review`,
  "self-review this PR", "review my PR and fix what it finds". Requires
  HERDR_ENV=1.
---

# Self-Review

Reviewer tab → [[multi-agent-pr-review]] `--yolo` → watcher → fix phase here ([[pr-watch]]'s `address.md`) → optional next round.

This session stays the **author**: it never reviews. The tab is the **reviewer**: it never edits. The watcher is the hand-off between them.

## Inputs

| Input | Default |
|---|---|
| PR URL | `gh pr view --json url` in the current checkout |
| `--rounds <n>` | `1`. Each extra round re-reviews after the fixes are pushed. Max `3`. |
| `--no-push` | Push the fixes. With this flag: commit locally, skip the push and the comment replies. |
| `--yolo` | Skip the staffing confirmation. |

Invoking the skill is the consent to fix, commit, and push. The only interactive gate is the staffing line (step 3), which `--yolo` skips.

## Steps

### 1. Preflight

All must hold; stop and say which one failed otherwise.

- `test "${HERDR_ENV:-}" = 1`. Load the [[herdr]] skill for CLI mechanics.
- [[pr-watch]] SKILL.md step 1 (my open PR, clean checkout on its branch, everything pushed). The reviewer reads GitHub, so unpushed work is unreviewed work. Someone else's PR → use [[multi-agent-pr-review]] directly.

Record: `URL`, `OWNER/REPO`, `NUM`, `HEAD` (`gh pr view --json headRefOid`), `DATE` (`date +%F`), `PR_KEY` (`<repo-short>-<num>`, e.g. `ibs-1097`), `RESULT=/tmp/pr-review-$DATE/$PR_KEY/result.json`, `NAME=selfrev-$PR_KEY` (≤ 32 chars, `[a-z0-9-]`).

### 2. Clear stale results

A `result.json` from an earlier run fires the watcher at once. If `$RESULT` exists, rename it to `result.<unix-ts>.json`.

### 3. Staff the reviewer tab

Reuse when `herdr agent get $NAME` shows a live agent that is `idle` or `done` (a previous round or run): skip to step 4 with it.

Otherwise:

```bash
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" \
  --label "self-review $OWNER/$REPO#$NUM" --no-focus
```

Read `.result.tab.tab_id` and `.result.root_pane.pane_id`. Start the agent with the caller's kind (`herdr agent get "$HERDR_PANE_ID"` → `.result.agent.agent`), staffed on the **review** row of [[herdr-dispatch]]'s staffing table, using that skill's per-kind flag syntax:

```bash
herdr agent start "$NAME" --kind <kind> --pane <root-pane-id> -- <model/thinking flags>
```

State the staffing line (`staffing: pi / claude-opus-5-5 / high`). Attended: let the user correct it first. `--yolo`: proceed.

### 4. Hand off the review

Send one plain-language prompt (works in every harness; no slash commands):

```
Self-review requested by the PR author. Use the multi-agent-pr-review skill with --yolo on <URL>.
Review head <HEAD>. Write artifacts under /tmp/pr-review-<DATE>/<PR_KEY>/.
This is a self-authored PR: post the review as COMMENT, as the skill describes.
When result.json is written, stop.
```

```bash
herdr agent prompt "$NAME" "<prompt>"
```

Then confirm it is `working` (`herdr agent get "$NAME"` → `.result.agent.agent_status`). Still `idle` → `herdr agent read "$NAME" --source visible --lines 10`; a pasted-but-unsent prompt needs `herdr agent send-keys "$NAME" enter`. Step 4 is done when the status is `working`.

### 5. Arm the watcher

The watcher fires when the reviewer has a result for this head, or when the reviewer stops without one (finished, asking a question, or gone):

```sh
test -s "$RESULT" && jq -e --arg h "$HEAD" '.status == "skipped" or .head_sha == $h' "$RESULT" >/dev/null && exit 0
s=$(herdr agent get "$NAME" 2>/dev/null | jq -r '.result.agent.agent_status' 2>/dev/null)
case "${s:-gone}" in idle|done|blocked|gone) exit 0 ;; esac
exit 1
```

Substitute the real values into the condition (it runs in a fresh shell). Arm it with the harness's background wake, timeout 2 hours:

| Harness | Watcher |
|---|---|
| pi | `until` with `action: "start"`, `condition`: the check above, `intervalSeconds: 60`, `timeoutSeconds: 7200`, `wake: "agent"`, `instruction`: "Self-review of `<URL>` finished. Run the fix phase in the self-review skill's `fix-phase.md` with: URL, HEAD, RESULT, NAME, tab id, rounds left, push mode." |
| Claude Code | Write the check to `/tmp/pr-review-$DATE/$PR_KEY/watch.sh`, then `Bash` with `run_in_background: true`: `timeout 7200 sh -c 'until sh <watch.sh>; do sleep 60; done'`. Its completion notification is the wake. |
| Other | Run the same loop in the foreground. |

Report: tab id, agent name, staffing line, watcher id. Then return control to the user — this session keeps working on other things until the wake.

### 6. On wake

Read `fix-phase.md` in this skill's directory and follow it.
