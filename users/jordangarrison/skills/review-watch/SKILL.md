---
name: review-watch
description: >-
  Use to keep my review of someone else's PR current after I commented or
  requested changes: watches the PR and, on each new push, runs one follow-up
  [[multi-agent-pr-review]] `--yolo` focused on the new commits and whether my
  earlier findings are fixed. Stops when I approve, the PR merges or closes, or
  it goes quiet for 3 days. Reviews first if I haven't reviewed it yet. The
  one owner of follow-up reviews: [[slack-pr-review]] hands its non-approving
  reviews here. For my own PRs, use [[pr-watch]]. Triggered by
  `/review-watch`, "keep watching the PR I reviewed", "re-review it when they
  push".
---

# Review Watch

Arm a gate on a PR I reviewed without approving → wake on a new head → one follow-up review through [[multi-agent-pr-review]] → stop when I approve, the PR merges or closes, or it goes quiet.

This session is the **reviewer**; [[pr-watch]] is the author's side. The review itself is always [[multi-agent-pr-review]]: this skill only decides *when* to call it. It posts nothing but those reviews: no Slack, no merges, no edits to the PR. Callers that signal elsewhere, like [[slack-pr-review]]'s reactions, pass `--on-round`.

This is the **one owner of follow-up reviews**: every rule about when to re-review lives here, whether I started the review by hand or a Slack pass did.

## Inputs

| Input | Default |
|---|---|
| PR URL | required |
| `--quiet <duration>` | `72h`. Stop after this long with no new commit. |
| `--interval <duration>` | `5m` |
| `--yolo` | Passed to the first review when this skill runs it (step 2). |
| `--on-round <instruction>` | Run after each recorded round, with its verdict and review URL. Set by callers (e.g. [[slack-pr-review]] updates the verdict reaction). |

Follow-up reviews always run with `--yolo`: invoking this skill is the standing authorization to post them under my name, so the core's `--yolo` machine gates apply to every one.

## Steps

### 1. Preflight

All must hold; stop and say which one failed otherwise.

- The PR resolves and is open, and its author is not me (`gh api user -q .login`). My own PR → [[pr-watch]] or [[self-review]].
- The main clone `~/dev/<owner>/<repo>` exists (the review core needs it).
- Not already watched here: the state file `~/.cache/review-watch/<owner>-<repo>-<num>.json` is missing, or its `watch_id` is not running (`until` `action: "status"`). Running → report the watch and stop.

### 2. My verdict review

A **verdict review** is a review I posted that is `APPROVED`, `CHANGES_REQUESTED`, or `COMMENTED` with a body. Replies in inline threads are empty-body `COMMENTED` reviews and don't count. Read my latest one:

```bash
gh api --paginate repos/<owner>/<repo>/pulls/<num>/reviews | jq -s --arg me <login> \
  '[.[][] | select(.user.login == $me) | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
     or (.state == "COMMENTED" and (.body // "") != ""))] | last | {state, commit_id, html_url}'
```

| Found | Action |
|---|---|
| none | Run [[multi-agent-pr-review]] on the URL (with `--yolo` if given). It skipped the PR → report `skip_reason`, stop. Otherwise read again. |
| `APPROVED` | Nothing to watch. Report, stop. |
| `CHANGES_REQUESTED` or `COMMENTED` | Arm (step 3). |

### 3. Arm

Write the state file (create the directory):

```json
{
  "repo": "<owner>/<repo>", "num": 12, "url": "<URL>", "pr_key": "<repo-short>-<num>",
  "me": "<login>", "quiet_hours": <--quiet in hours>,
  "armed_at": "<date -u +%Y-%m-%dT%H:%M:%SZ>",
  "reviewed_head": "<commit_id>", "review_url": "<html_url>",
  "seen_head": "<commit_id>",
  "on_round": "<--on-round instruction, or null>",
  "rounds": []
}
```

`reviewed_head` is the head my latest review covers, the base for the next follow-up. `seen_head` is the last head this watch handled, the gate's cursor. `pr_key` matches the core's artifact directory. `on_round` lives here so it survives compaction.

The state file also marks the PR as **owned**: [[slack-pr-review]] skips a PR while its state file exists.

Then, **in a separate tool call** (the gate checks at once and must see the file), arm the gate `~/.agents/skills/review-watch/check.sh <state-file>`:

| Harness | Watcher |
|---|---|
| pi | `until` with `action: "repeat"`, `condition`: the gate, `intervalSeconds`: the interval, `timeoutSeconds: 1209600` (14-day backstop), `immediate: false`, `label`: `review-watch <owner>/<repo>#<num>`, `quickRef`: the URL, `instruction`: "review-watch tick for `<URL>`. Follow review-watch SKILL.md step 4 with state file `<path>`." |
| Claude Code | `Bash` with `run_in_background: true`: `sh -c 'until <gate> <state-file>; do sleep <interval-secs>; done'`. Its completion is the wake; re-arm after step 4 unless it stopped. |

`repeat`, not `start`: the gate keeps every tick on an unchanged PR away from the model, `repeat` hands the instruction over on every wake, and it stays armed between reviews. A `start` watch ignores `instruction`, so its wake names only the label.

Write the watch id to `watch_id`. Report: PR, my verdict and review URL, state file, watch id, stop conditions. Then return control; this session keeps working until a wake.

### 4. On wake

Run the gate again; the wake may be stale. First match wins:

| Gate prints | Action |
|---|---|
| nothing (exit 1) | Nothing new. End the turn; the watch stays armed. |
| `pr:MERGED` or `pr:CLOSED` | Stop (step 5), done. |
| `approved` | I approved outside this watch. Record my verdict review as a round, then stop (step 5), done. |
| `quiet` | Stop (step 5), quiet. |
| `head:<seen>..<new>` | Handle the push (below). |

**Handle the push.** First match wins:

1. **Already reviewed.** My verdict review (step 2's query) has `commit_id == <new>`: another caller reviewed this head. Record it as the round.
2. **Base merges only** ("Update branch"): fetch the review ref as in the core's "Follow-Up Reviews", then `git -C <clone> rev-list --no-merges <reviewed_head>..origin/pr/<num> ^origin/<base>` prints nothing. The author changed nothing; set `seen_head` to `<new>`, no review.
3. **Follow-up review.** Run [[multi-agent-pr-review]] with `--yolo` on the URL as a follow-up review: my prior review is `review_url` at head `reviewed_head`. Its "Follow-Up Reviews" flow scopes the review to the new commits and checks each earlier finding. Then read the `result.json` it wrote in this step, under `/tmp/pr-review-<date>/<pr_key>/`:
   - `posted` → record the round from it.
   - `skipped` (merged or closed meanwhile) → stop (step 5).
   - none → the review failed. Set `seen_head` to `<new>` so the failure isn't retried every tick, report it, and keep watching; the next push tries again.

**Record a round:** append `{head, verdict, review_url, at}` to `rounds`; set `reviewed_head` and `seen_head` to its head and `review_url` to its URL. The core reviews the head current at posting, which can be newer than `<new>`. Run `on_round`, if set, with the round's verdict and review URL. Verdict `APPROVE` → stop (step 5). Otherwise report one line and end the turn:

```
<owner>/<repo>#<num> → <verdict> <review_url> (<reviewed7>..<head7>) · attention: <needs_attention or none>
```

### 5. Stop and report

- pi: `until` `action: "complete"` on `watch_id` when done; `action: "cancel"` when quiet or stopped by hand ("stop watching <PR>"). Claude Code: don't re-arm.
- Delete the state file. GitHub holds the reviews; a later `/review-watch` starts from them.

```
PR:        <URL>  (<open | merged | closed>)
Follow-ups: <n> — <verdict> <review_url> (<head7>), one per round
Stopped:   approved | merged | closed | quiet <n>h | by hand
Attention: <needs_attention items from the rounds>
```
