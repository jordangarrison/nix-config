---
name: sre-review-rollover
description: Use when yesterday's SRE-review PR posts in Flocasts #infra-private got no review and need to be re-posted to today's bot thread. Finds your own replies in yesterday's "SRE Review Thread", filters to PRs still needing review (open, non-draft, not approved), and re-posts each to today's thread with a `[rollover from <slack-link|yesterday>]` prefix — or, as a lighter alternative, bumps the original post in place with a gated `:travolta:` reaction. Triggered by `/sre-review-rollover`, "rollover yesterday's SRE reviews", or "give yesterday's PRs a travolta bump".
---

# SRE Review Rollover

## Overview

Re-post yesterday's un-reviewed PRs into today's SRE review thread, keeping a link back to the original post so context is preserved without quoting the old message.

**Core flow:** identify me → find yesterday's bot thread → list my replies → filter to PRs still needing review → find today's bot thread → show the plan → post one rollover reply per eligible PR.

Companion to the [[sre-review]] skill. This skill never creates a top-level message — it only replies inside today's bot-created thread, same as `sre-review`.

## When to Use

- User runs `/sre-review-rollover` (with or without args)
- User says "rollover yesterday's SRE reviews", "re-post the SRE PRs that didn't get reviewed", "bump yesterday's PRs into today's thread"
- The morning after a hot streak of posts that landed late and got no eyes

**Do NOT use** for:
- General Slack reposting
- Rolling over someone else's PRs (this skill filters to *your* posts only)
- Bumping a single PR — use `/sre-review` again with the PR URL, that's simpler

## Constants

- Channel name: `#infra-private`
- Channel ID: `CF7SPS45P`
- Workspace: `flocasts.slack.com`
- Bot thread marker: text contains both `:thread:` and `review thread` (case-insensitive)
- My reply format (per `sre-review`): `<description>: <github-pr-url>` — one PR per reply
- Rollover message format (exact):
  ```
  [rollover from <PERMALINK|yesterday>] <description>: <pr-url>
  ```
  The `<url|text>` mrkdwn syntax keeps Slack from rendering a message preview of the original post. The GitHub PR URL will still unfurl normally.
- Identity cache: `~/.claude/skills/sre-review-rollover/.identity.json` → `{ "slack_user_id": "U…", "email": "…" }`
- Day cache: `~/.claude/skills/sre-review/.cache.json` (shared with `sre-review` for today's thread lookup)
- Bump reaction: `travolta` — "this PR isn't getting the love it deserves, reminding everyone" (added via `mcp__claude_ai_Slack__slack_add_reaction`, emoji name without colons)

## Steps

### 1. Resolve identity (cached)

Read `~/.claude/skills/sre-review-rollover/.identity.json`. If present and `slack_user_id` looks valid (`^U[A-Z0-9]+$`), use it.

If missing or invalid:
- Read the user's email from CLAUDE memory (`userEmail` in the system context) or ask if absent.
- Call `mcp__claude_ai_Slack__slack_search_users` with the email.
- Persist:
  ```bash
  cat > ~/.claude/skills/sre-review-rollover/.identity.json <<EOF
  {"slack_user_id":"<U…>","email":"<email>"}
  EOF
  ```

### 2. Find yesterday's bot thread

Compute yesterday in America/Chicago:
```bash
TZ=America/Chicago date -d 'yesterday' +%F
```

Call `mcp__claude_ai_Slack__slack_read_channel` on `CF7SPS45P` with `limit: 80` (covers ~2 workdays).

Filter for the most recent message where ALL hold:
- Posted on yesterday's date (compare `ts` against yesterday in America/Chicago)
- Text contains `review thread` (case-insensitive)
- Text contains `:thread:` OR `bot_id` is set / `subtype == "bot_message"`

If zero matches: stop, tell user "No SRE review thread found for yesterday — nothing to roll over." Do not write any cache.

Save yesterday's `thread_ts` and `permalink`.

### 3. Read yesterday's thread, extract my PR posts

Call `mcp__claude_ai_Slack__slack_read_thread` with channel `CF7SPS45P` and `thread_ts` from step 2.

For each reply, keep only those where `user == <slack_user_id from step 1>`. For each kept reply, extract:
- `description` = text before the last `: https://github.com/...` segment
- `pr_url` = the GitHub PR URL (regex `https://github\.com/[^/\s]+/[^/\s]+/pull/\d+`)
- `original_permalink` = the message's permalink. If the API response doesn't include it, build it:
  ```
  https://flocasts.slack.com/archives/CF7SPS45P/p<TS_DOTS_REMOVED>?thread_ts=<PARENT_TS>&cid=CF7SPS45P
  ```
  where `TS_DOTS_REMOVED` = reply `ts` with the `.` removed.

If no replies from me: stop, tell user "You had no posts in yesterday's SRE review thread."

### 4. Check each PR's review status

For each `pr_url`, run:
```bash
gh pr view <pr_url> --json state,isDraft,reviewDecision,mergeStateStatus,title
```

Classify:

| Status | Action | Reason shown to user |
|---|---|---|
| `state == "MERGED"` | skip | merged |
| `state == "CLOSED"` (and not merged) | skip | closed |
| `isDraft == true` | skip | draft |
| `reviewDecision == "APPROVED"` | skip | approved (ready to merge) |
| `state == "OPEN"` AND not draft AND `reviewDecision in {null, "REVIEW_REQUIRED", "CHANGES_REQUESTED"}` | **roll over** | needs review |

`mergeStateStatus` is informational only — it shouldn't gate rollover (a PR can be `BEHIND` but still needing review).

If `gh pr view` fails for a URL: skip with reason "gh lookup failed", surface the error in the preview.

If zero PRs are eligible: stop, tell user "Nothing to roll over — your posts from yesterday are all merged/approved/closed." Show the skipped list anyway so they have visibility.

### 5. Find today's bot thread

Reuse the `sre-review` cache at `~/.claude/skills/sre-review/.cache.json`.

- Cache hit on today's date: use cached `thread_ts` + `permalink`.
- Cache miss / stale / missing: scan with the same logic as step 2 but for today's date. Write the cache (same format as `sre-review`).
- Zero matches today: stop, tell user "Today's SRE review thread hasn't been posted yet — wait for the ~9 AM CDT bot post." Do NOT create a top-level message.

### 6. De-dupe against today's thread

Read today's thread with `slack_read_thread`. For each eligible PR, check whether any reply in today's thread already contains its PR URL. If yes, skip it with reason "already in today's thread".

This prevents double-rolling if the skill ran earlier today, or if the user manually re-posted.

### 7. Show the plan

Invoking this skill *is* the consent to post — no y/n gate. Show the user the plan (for auditability, not approval), then proceed straight to step 8. Show a table:

```
Channel:        #infra-private
Yesterday:      <permalink to yesterday's bot thread>
Today:          <permalink to today's bot thread>

Rolling over (N):
  ✓ <desc>: <pr-url>
  ✓ <desc>: <pr-url>

Skipping (M):
  · <desc>: <pr-url>   (merged)
  · <desc>: <pr-url>   (approved)
  · <desc>: <pr-url>   (already in today's thread)
```

For each rollover, also show the exact final message text so the user sees the `[rollover from …]` prefix being posted.

Only pause for input if the user explicitly asked for a dry-run/preview, or if step 4 surfaced errors that make eligibility ambiguous.

### 8. Post (one reply per eligible PR)

For each eligible PR, call:
```
mcp__claude_ai_Slack__slack_send_message
  channel_id: CF7SPS45P
  thread_ts:  <today's thread_ts from step 5>
  text:       [rollover from <ORIGINAL_PERMALINK|yesterday>] <description>: <pr-url>
```

Post sequentially, not in parallel — keeps the order in-thread deterministic and avoids rate-limit thrash.

If a post fails with `thread_not_found` / `message_not_found`: delete `~/.claude/skills/sre-review/.cache.json`, re-run step 5 once, then retry the failed post. If it still fails, stop and report which PRs got posted vs. didn't.

Report final status with reply permalinks if the API returns them.

## Lighter alternative: `:travolta:` bump

A full rollover re-posts the PR into today's thread. When a PR is only mildly stale — or the user just wants to nudge without adding a new reply — reacting `:travolta:` on the **original** post is the lighter touch: it's the channel's "this PR isn't getting the love it deserves, reminding everyone" signal. Use it when the user says "just bump them" / "give them a travolta" instead of a re-post.

Same eligibility gate as a rollover applies — only bump PRs that genuinely need review (step 4 classified them "needs review"). React on the message carrying the PR URL:
```
mcp__claude_ai_Slack__slack_add_reaction
  channel_id: CF7SPS45P
  message_ts: <ts of the post you're bumping>
  emoji:      travolta
```

This and a re-post are alternatives, not both — pick one per PR with the user. A `:travolta:` on yesterday's post keeps the conversation in the original thread; a rollover surfaces it in today's. The single-PR bump-in-place case is also covered by [[sre-review]]'s "Bumping a stale post" section.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Rolling over a PR that already got merged overnight | Always run step 4 (`gh pr view`) — never trust yesterday's intent. |
| Quoting yesterday's full message text into today's thread | Use the `<url\|text>` mrkdwn link, not a raw URL. Slack won't render a preview for the linked form. |
| Posting a top-level message because today's bot thread is missing | Step 5 must find a thread or STOP. Never fall back to top-level. |
| Double-rolling because the skill ran twice | Step 6 de-dupes by PR URL substring in today's thread. Don't skip it. |
| Wrong day's "yesterday" (UTC vs CDT) | Use `TZ=America/Chicago date -d 'yesterday' +%F`, not UTC. The bot operates on Central time. |
| Rolling over someone else's PRs | Step 3 filters by your Slack user ID. Don't widen the filter. |
| Posting in parallel | Sequential posts only — preserves thread order, avoids rate-limit retries. |
| `:travolta:` on a PR that's already getting reviewed | Same gate as rollover — only bump PRs classified "needs review" in step 4. Don't travolta merged/approved/draft PRs. |
| Both re-posting AND travolta-ing the same PR | They're alternatives. Pick one per PR with the user, not both. |

## Red Flags — STOP

- Step 2 found no yesterday thread → STOP, nothing to roll over.
- Step 5 found no today thread → STOP, don't post top-level.
- Identity lookup returns multiple users for the email → STOP, ask user which is theirs.
- A PR URL in your post doesn't match the GitHub regex (e.g. you posted a Linear link) → skip that one with reason "non-GitHub URL".
- Zero eligible PRs after filtering → don't post anything; report that the list was empty (with the skipped reasons).

## Security

Channel ID, workspace URL, and Slack user IDs aren't credentials but DO leak org structure. Cache files live under `~/.claude/skills/sre-review-rollover/` — do not sync to a public dotfiles repo.
