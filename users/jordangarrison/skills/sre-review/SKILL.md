---
name: sre-review
description: >-
  Use when posting a PR for SRE review in Flocasts #infra-private — finds
  today's "SRE Review Thread" bot post and replies with the PR link. Also handles
  bumping a stale post that isn't getting reviewed via a gated `:travolta:`
  reaction. Triggered by `/sre-review`, phrases like "post this to the SRE review
  thread" / "drop in #infra-private review thread", or "bump my PR" / "give it a
  travolta".
---

# SRE Review Thread Poster

## Overview

Post a PR link as a reply to today's SRE review thread in Flocasts `#infra-private`. The thread is created daily at ~9 AM CDT by the **SRE Review Thread** bot.

**Core flow:** detect PR → find today's bot thread → show what's being posted → post reply.

## Constants

- Channel name: `#infra-private`
- Channel ID: `CF7SPS45P`
- Bot author marker: message text contains both `:thread:` and `review thread` (case-insensitive)
- Message convention: `<short description>: <PR url>` — one reply per PR
- Cache file: `~/.claude/skills/sre-review/.cache.json` (per-day thread lookup cache)
- Bump reaction: `travolta` — "this PR isn't getting the love it deserves, reminding everyone" (added via `mcp__claude_ai_Slack__slack_add_reaction`, emoji name without colons)

## When to Use

- User runs `/sre-review` (with or without args)
- User asks to post a PR to the SRE review thread / `#infra-private` review thread
- User says "submit this for SRE review" in a repo with an open PR

**Do NOT use** for general Slack posting — only this specific daily thread.

## Inputs

Skill accepts optional args:

| Form | Behavior |
|---|---|
| `/sre-review` | Auto-detect: run `gh pr view --json url,title,number` in cwd. Description = PR title |
| `/sre-review <description>` | Auto-detect PR, override description |
| `/sre-review <description>: <pr-url>` | Use literal description + URL, skip `gh` |
| `/sre-review <pr-url>` | Use URL, fetch title via `gh pr view <url> --json title` for description |

Detect form by: contains `https://github.com/` → has URL. Contains `: http` → full literal.

## Steps

### 1. Resolve PR

If URL not given, run from cwd:
```bash
gh pr view --json url,title,number
```

If `gh` errors with "no pull requests found": stop and ask user for the PR URL. Do not guess.

Final message format (exact):
```
<description>: <url>
```

Trim trailing whitespace; lowercase the first letter of description if user didn't capitalize intentionally (match channel convention — see source examples).

### 2. Find today's review thread (cached per day)

> **Re-resolve before EVERY post.** Recompute `TZ=America/Chicago date +%F` and
> re-read the cache each time you post — never hold a `thread_ts` in memory and
> reuse it across posts. A long-running session (a watch loop, a review
> back-and-forth, repeated re-pings) can cross the ~07:00 CDT daily rollover, and
> reusing an earlier `thread_ts` silently posts to *yesterday's* thread. The cache
> file is per-day and self-corrects; a variable you cached in-session does not.

**First, check the cache.** Read `~/.claude/skills/sre-review/.cache.json` if it exists:
```json
{ "date": "YYYY-MM-DD", "thread_ts": "1234567890.123456", "permalink": "https://..." }
```

`date` is today in America/Chicago. Compute today's date with:
```bash
TZ=America/Chicago date +%F
```

- Cache hit (`date` matches today): use cached `thread_ts` + `permalink`. Skip the channel scan entirely.
- Cache miss / stale / missing file: do the scan below, then write fresh cache.

**Scan logic** (only on cache miss):

Use `mcp__claude_ai_Slack__slack_read_channel` with channel `CF7SPS45P`, limit 30 (covers a full workday).

Filter for the most recent message where ALL hold:
- Posted today (compare `ts` against today's date in America/Chicago)
- Text contains `review thread` (case-insensitive)
- Text contains `:thread:` OR is from a bot (`bot_id` set or `subtype: bot_message`)

If zero matches: stop, tell user "No SRE review thread found for today in #infra-private — bot may not have posted yet." Do NOT post a top-level message. Do NOT write the cache.

If multiple matches: pick latest by `ts`.

After picking the thread, **write the cache** (overwrite any prior content):
```bash
cat > ~/.claude/skills/sre-review/.cache.json <<EOF
{"date":"$(TZ=America/Chicago date +%F)","thread_ts":"<ts>","permalink":"<permalink>"}
EOF
```

Save the matched message's `ts` — this is the `thread_ts` for the reply.

**Cache invalidation:** if step 4 (post) fails with a thread-not-found / `thread_not_found` / `message_not_found` error, delete `.cache.json` and re-run from step 2 once. If it fails again, stop and report.

### 3. Show what's being posted

Invoking this skill *is* the consent to post — no y/n gate. Show the user exactly what's going out (for auditability, not approval), then proceed straight to step 4:
```
Channel:  #infra-private
Thread:   <permalink to bot message>
Message:  <description>: <pr-url>
```

Only pause for input if the user explicitly asked for a dry-run/preview, or if something upstream is ambiguous (e.g., couldn't resolve the PR).

### 4. Post

```
mcp__claude_ai_Slack__slack_send_message
  channel_id: CF7SPS45P
  thread_ts:  <ts from step 2>
  text:       <description>: <url>
```

Confirm posted; share the reply permalink if the response includes one.

## Bumping a stale post (`:travolta:`)

When a PR you already posted to the thread isn't getting reviewed, you can react `:travolta:` on **your own reply** to remind everyone — it's the channel's "this PR isn't getting the love it deserves" nudge. This is a separate action from the initial post; trigger it when the user says "bump my PR", "nobody's reviewed X", or "give it a travolta".

**Gate it on genuine starvation — never auto-add it to a fresh post.** Before reacting, confirm the PR actually lacks review love:
- The reply has no review reactions yet (`eye-twitch`, `mega-approved`, `reverse`, `dumpsterfire`) — check the `reactions` array via `slack_read_thread`.
- `gh pr view <url> --json reviewDecision,reviews` shows no review activity (`reviewDecision` null / `REVIEW_REQUIRED`, no review threads).
- Enough time has passed that silence is real, not just "posted five minutes ago."

If all hold, react:
```
mcp__claude_ai_Slack__slack_add_reaction
  channel_id: CF7SPS45P
  message_ts: <ts of your reply carrying the PR url>
  emoji:      travolta
```

Adding a duplicate succeeds silently, so re-bumping is harmless. Don't post a new "please review" message as a substitute — the reaction *is* the bump. For rolling over yesterday's starved PRs into today's thread, use [[sre-review-rollover]] instead.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Posting top-level (not in thread) | Always pass `thread_ts`. Refuse to post if step 2 returned no match. |
| Wrong day's thread | Filter by today's date in America/Chicago TZ, not UTC. Bot posts ~9 AM CDT. |
| Stale cache from yesterday | Always compare cache `date` to `TZ=America/Chicago date +%F` before reuse. Different = rescan. |
| Reusing a `thread_ts` resolved earlier in the same session | Re-check the date + re-read the cache before *every* post, not just the first. A session that spans the ~07:00 CDT rollover will otherwise post to the wrong day's thread. |
| Posting silently | No y/n gate, but always show channel/thread/message as you post — the user must be able to audit what went out under their name. |
| Auto-detecting on a non-PR branch | If `gh pr view` fails, ask user — don't fall back to a guess. |
| Multi-line / formatted message | Convention is one line: `<desc>: <url>`. No bullets, no bold, no Slack mentions. |
| `:travolta:` on a freshly posted PR | The bump reaction is only for PRs that have sat without review. Don't add it at post time — gate it on genuine starvation (no review reactions, no GitHub review activity, real time elapsed). |

## Security

Channel ID and name are not credentials but DO leak internal org structure. This skill is local-only — do not sync `~/.claude/skills/sre-review/` to a public dotfiles repo.

## Red Flags — STOP

- No today-bot match found → STOP, tell user. Don't post top-level.
- `gh pr view` fails and no URL arg → STOP, ask for URL.
- User explicitly asked for dry-run / "show me first" → preview only, wait for a go-ahead before sending.
