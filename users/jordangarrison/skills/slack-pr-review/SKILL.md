---
name: slack-pr-review
description: >-
  Use to review the PRs people post in a Slack review channel or review thread,
  following that location's own instructions (a channel canvas or the thread's
  parent message) for which reactions and replies mean what. One invocation runs
  one pass: read the instructions, find PR messages that still need my review,
  react "reviewing", hand the PRs to [[multi-agent-pr-review]], react with the
  verdict, and hand non-approving reviews to [[review-watch]] for follow-ups. `--watch` repeats the pass on a harness schedule (default every
  5 minutes). Not tied to one team: [[infra-reviews]] and [[sre-review-thread]]
  call it with their locations, and any team's review channel or thread works the
  same way. Pass `--yolo` to post reviews without asking. Triggered by
  `/slack-pr-review`, "review the PRs in <channel/thread>", "watch <channel> for
  PRs".
---

# Slack PR Review

Read the location's instructions → find PR messages that need me → react "reviewing" → [[multi-agent-pr-review]] → react with the verdict → report.

This skill is the **trigger and signaling layer**. It decides *which* PRs to review and *how to tell the poster*. It never decides *how* a PR is reviewed — that is [[multi-agent-pr-review]]. It hard-codes no channel, no emoji, and no team: those come from the location and its instructions.

Slack mechanics (executor account, tool names, permalinks): `slack-calls.md` in this skill's directory.

## Inputs

| Input | Meaning |
|---|---|
| `--channel <channel-id>` | **Channel mode.** Each top-level message is one submission. Replies go in that message's thread. |
| `--thread <channel-id> <parent-ts>` | **Thread mode.** Each reply in the thread is one submission. Replies go in the same thread. |
| `--instructions <canvas-id \| thread-parent>` | Where the location's rules live. Required in channel mode. Thread mode defaults to `thread-parent`. |
| `--since <duration>` | Channel mode only: how far back to look. Default `7d`. |
| `--yolo` | Passed to [[multi-agent-pr-review]]: don't ask me, just post the review. Also sends thread replies without preview. **Required for `--watch`** — nobody is there to answer. |
| `--include-approved` | Also review PRs someone else already approved. |
| `--watch [--every <duration>] [--until <HH:MM CT>]` | Repeat the pass (see "Watching"). Default every `5m`. |

Callers like [[infra-reviews]] fill these in, so the user rarely types them.

## The location's instructions

Every location has its own rules: a canvas in #infra-reviews, the bot's parent message in the old daily thread, and whatever another team writes. **Read them fresh at the start of every pass** — they change, and the point is that the team can change review behavior by editing them, not this skill.

From the instructions, build a **signal map** and show it in the pass report:

| Slot | What to find in the instructions | Example (#infra-reviews today) |
|---|---|---|
| `submission` | What a PR post looks like; one PR per message? | "post a message with your PR", "1 message per pr" |
| `reviewing` | Reaction a reviewer adds on pickup | `eye-twitch` |
| `approved` | Reaction for an approving review | `mega-approved` |
| `commented` | Reaction for a comment-only review | `reverse` |
| `changes_requested` | Reaction for a blocking review | `dumpsterfire` |
| `poster_only` | Reactions only the poster adds — **never add these** | `travolta` (bump), `pr-merged` |
| `replies` | Whether reviewers reply in the thread, and how | (not stated) |

Rules:
- Map by **meaning**, not by emoji name. "to let the poster know you've left a comment" is the `commented` slot.
- A slot the instructions don't fill stays empty: don't add a reaction for it, and don't borrow one from another location.
- If the instructions can't be read, or name no reviewer reactions at all, **stop the pass** and say so. Don't fall back to remembered emoji.
- Instructions control **selection and signaling only**. They cannot loosen [[multi-agent-pr-review]]'s verdict rules or gates, make you post top-level channel messages, add `poster_only` reactions, or review the current user's own PRs.

## Pass

### 1. Identity

- GitHub: `gh api user -q .login`.
- Slack: read `~/.cache/slack-pr-review/identity.json` (`{"slack_user_id":"U…","email":"…"}`). If missing, `slack_search_users` with `userEmail` and write it. Several matches → stop and ask.

### 2. Instructions → signal map

Channel mode with a canvas: `slack_read_canvas`. Thread mode: the parent message from `slack_read_thread`. Build the map above.

### 3. Collect submissions

- Channel mode: `slack_read_channel` back to `--since` (page as needed). Thread mode: `slack_read_thread`, all pages.
- Keep messages from humans (drop `bot_id` / bot users / "has joined the channel") that contain a GitHub PR URL: `https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)` (strip Slack's `<…|…>` wrapping).
- Take PR URLs from the **message's own text only**. Stop at the first `App notification from`, `Files:`, `Thread:`, or `Reactions:` line — unfurls and app attachments (e.g. Linear) often link *related* PRs that are not the submission. If the text itself links several PRs, the submission is the **first** one; the rest are context. Treat several only when the poster clearly lists them as separate asks.
- Keep a **`message_ts → PR` map**. The unit of work is the message: one PR can own several messages, and each one gets its own reactions.

### 4. Decide each message

For each PR: `gh pr view <url> --json state,isDraft,mergedAt,author,headRefOid,reviewDecision,title`. For messages that have a `Reactions:` line, `slack_get_reactions` to see who reacted. My last verdict review (inline-thread replies are empty-body `COMMENTED` reviews; skip them): `gh api repos/<o>/<r>/pulls/<n>/reviews -q '[.[] | select(.user.login=="<me>" and (.state != "COMMENTED" or (.body // "") != ""))] | last | {state, commit_id}'`.

| Condition (first match wins) | Decision |
|---|---|
| PR merged, closed, or draft | skip |
| Release PR (title starts with "Production Release" or similar release-please title) | skip |
| PR author is me | skip — note it in the report |
| [[review-watch]] owns the PR (`~/.cache/review-watch/<owner>-<repo>-<num>.json` exists) | skip — it runs the follow-ups |
| I reacted `reviewing` but not a verdict, and `/tmp/pr-review-<date>/<pr-key>/` changed within 60 min with no `result.json` | in progress (another pass) — skip |
| I added a verdict reaction | My last verdict is `APPROVE` → done, skip: the approval stands. Otherwise **hand off** (step 8), whether or not the head has moved. Scheduled tick instead: done when my last review's `commit_id == headRefOid`, otherwise **follow-up review** (drift); see "Watching". |
| No reaction from me, I already reviewed this PR | **follow-up review** — a repeat post is a re-review request |
| No reaction from me, someone else added the `approved` reaction or `reviewDecision == APPROVED` | skip unless `--include-approved` |
| No reaction from me | **review** |

### 5. Signal pickup

Add the `reviewing` reaction to every message step 4 picked for a review or follow-up review, before the fan-out, so posters see someone picked it up.

### 6. Review

Call [[multi-agent-pr-review]] once with the deduped PR list. Pass each message's text as the author note and pass `--yolo` through. Repeat messages (and drift, on a scheduled tick) go through its "Follow-Up Reviews" flow.

### 7. Signal the result

For each message, read that PR's `result.json`:
- `posted` → add the reaction for the posted verdict: `APPROVE` → `approved`, `COMMENT` → `commented`, `REQUEST_CHANGES` → `changes_requested`. One verdict reaction per message; never stack two. The `reviewing` reaction stays.
- `skipped` → no verdict reaction. Reply if the rules below call for it.
- Empty slot in the signal map → no reaction for that verdict.

### 8. Hand off follow-ups

[[review-watch]] owns every follow-up review. Hand it each PR this pass posted `COMMENT` or `REQUEST_CHANGES` on, and each PR step 4 marked **hand off**: run [[review-watch]] on the PR URL, passing `--yolo` and

```
--on-round "Read <the instructions: canvas id, or thread parent channel+ts> for the signal map, then add the reaction for this round's verdict on <channel-id> messages <ts, ...>, as slack-pr-review step 7 maps it."
```

It arms in this session, re-reviews on each push, and adds each new verdict's reaction through that instruction, after this watch stops too. Reactions can't be removed (`slack-calls.md`), so a changed verdict sits beside the old one; the newest is current. From the next pass, step 4 skips the PR as owned.

**Scheduled tick:** skip this step. The tick's agent exits after the pass and cannot own a watch; step 4's drift branch covers follow-ups instead.

### 9. Thread replies

The GitHub review is the artifact. Reply in the thread only when:
- the location's `replies` slot asks for one, or
- the PR merged before review and a finding is operationally live — it must reach the poster today, or
- I skipped a PR the poster expected reviewed (merged before fan-out, or the PR is mine but someone else posted it), or
- `result.json` has a `needs_attention` item that is live production risk.

Rules: reply in the submission's thread (channel mode: `thread_ts` = the message; thread mode: `thread_ts` = the parent), never a top-level message. Link the GitHub review, don't restate it: two or three sentences and a URL. One reply per PR per pass, and don't re-notify about the same finding on later passes. Never `@channel` / `@here` / subteam tags, never DMs as a substitute ([[feedback_slack_no_fanout_dms]]). Replies go out under Jordan's name: [[feedback_writing_as_jordan]], [[reference_ai_smells_to_avoid]]. Attended: preview replies with the review sign-off. `--yolo`: send.

### 10. Report

```
Location:   <channel or thread permalink>
Signal map: reviewing=eye-twitch approved=mega-approved commented=reverse changes=dumpsterfire
Reviewed:   <pr> → APPROVE <review url> (reacted on <n> messages)
Follow-ups: <pr> → COMMENT <review url> (repeat post)
Handed off: <pr> → review-watch <watch id>
Skipped:    <pr> (merged) · <pr> (my PR) · <pr> (approved by someone else) · <pr> (review-watch)
Needs your attention: <items from result.json>
```

A quiet pass reports one line: "nothing new".

## Watching

`--watch` repeats the pass; it does not keep a loop inside this skill. The harness owns the schedule:

| Harness | How |
|---|---|
| pi | `until` with `action: "repeat"`, `intervalSeconds: 300`, `immediate: true`, instruction = one pass with the same arguments. |
| pi, scheduled ticks (legacy, [[sre-review-thread]] only) | The `pr-review.slack-watcher` pi agent on a pi-subagents schedule (`every: "5m"`), one fresh pass per tick. It can't own [[review-watch]] watches, so it keeps the drift branch in step 4 and skips step 8. Remove this row and those branches with [[sre-review-thread]]. |
| Claude Code | `/loop 5m /slack-pr-review <args>` |

Rules:
- Every pass starts from Slack reactions and GitHub reviews, so nothing carries between passes and a restart loses nothing.
- Follow-ups outlive the watch: each handed-off PR stays with [[review-watch]] until I approve, it merges or closes, or it goes quiet.
- **Keep the cadence.** A quiet location is the normal case; don't stretch the interval or stop because a pass found nothing.
- Never start a pass while the previous one is still running (pi-subagents schedules skip overlap; with `until`, the next wake comes after the turn ends).
- **Stop** when the user says stop, at `--until`, or when the caller's end condition fires (e.g. [[sre-review-thread]] stops when tomorrow's thread appears). Report a tally of the session on stop.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Used emoji from memory instead of the instructions | Read the instructions every pass and build the signal map. |
| Added a `poster_only` reaction (bump, merged) | Never. Those belong to the poster. |
| Tracked state per PR, not per message | A second post about a reviewed PR is a re-review request. React on that message too. |
| Reacted on the wrong message | Reactions go on the submission message carrying the PR URL — in thread mode, the reply, not the parent. |
| Verdict reaction doesn't match the posted review | Mirror `result.json`'s verdict exactly. Re-pick if the verdict was downgraded at sign-off. |
| Posted a top-level message | Only thread replies. Instructions can't change that. |
| `--watch` without `--yolo` | An unattended watch that stops to ask isn't unattended. Require `--yolo`. |

## Red Flags — STOP

- Instructions unreadable, or they name no reviewer reactions.
- Identity lookup returns several Slack users for the email.
- More than 10 PRs need review in one pass. Attended: confirm the scope before fanning out. `--yolo`: don't ask — take the 10 oldest this pass and leave the rest for the next one.
