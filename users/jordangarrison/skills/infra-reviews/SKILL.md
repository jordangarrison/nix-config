---
name: infra-reviews
description: >-
  Use for the Flocasts #infra-reviews Slack channel, where each PR is its own
  top-level message. Modes: `post` (post my PR in the format the channel canvas
  defines), `bump` (gated `:travolta:`-style nudge on my PRs nobody has
  reviewed), `merged` (mark my merged PRs), and `review` (review other people's
  PRs via [[slack-pr-review]] + [[multi-agent-pr-review]]; `--watch` to keep
  watching). Every rule — post format, reaction meanings — is read from the
  channel canvas, not hard-coded here. Triggered by `/infra-reviews`, "post this
  for review", "post to infra-reviews", "bump my PR", "review the infra-reviews
  PRs", or the old `/sre-review` phrasing.
---

# #infra-reviews

The Flocasts review channel. Each PR is one top-level message; reactions go on that message; review conversation goes in its thread.

**The canvas is the source of truth.** This skill hard-codes only where the channel and canvas are. Post format and reaction meanings come from the canvas on every run, so the team changes behavior by editing the canvas, not this file.

## Constants

- Channel: `#infra-reviews`, ID `C0C9Q4HNVV3`
- Instructions canvas: `F0C9PAH4TK5` ("Channel Instructions", linked at the top of the channel)
- Slack mechanics: `../slack-pr-review/slack-calls.md`

## Read the canvas first (every mode)

`slack_read_canvas` with `canvas_id: "F0C9PAH4TK5"`. From it take:
- **Post format** — what a PR message must contain and in what order. Today the canvas says only "post a message with your PR" (the PR URL) and "1 message per pr".
- **Reactions by meaning** — the same signal map [[slack-pr-review]] builds (`reviewing`, `approved`, `commented`, `changes_requested`), plus the poster-side ones this skill uses: `bump` ("isn't getting the love it deserves") and `merged` ("your PR has been merged").

If the canvas can't be read: stop and say so. Don't post or react from memory.

## Modes

| Invocation | Mode |
|---|---|
| `/infra-reviews` or `/infra-reviews post [<desc>] [<pr-url>]` | post |
| `/infra-reviews bump [<pr-url>]` | bump |
| `/infra-reviews merged` | merged |
| `/infra-reviews review [--yolo] [--watch …]` | review |

`--yolo` on any mode: no previews held for approval, no questions. Everything done is still reported.

### post — my PR, one top-level message

1. **Resolve the PR.** URL given → use it. Otherwise `gh pr view --json url,title,number,body` in cwd. No PR found → stop and ask for the URL; don't guess.
2. **Check it isn't already posted.** `slack_read_channel` (last 14 days): if a message already links this PR, don't post a second one — the canvas asks for one message per PR. Offer `bump` instead.
3. **Compose from the canvas's post format.** Fill each field the canvas asks for from the PR (title, body, ticket from branch/title, etc.). Where the canvas leaves something open, use the plainest message that follows it: the PR URL on line one, then a one-line description (the PR title, or the user's `<desc>`). No bullets, bold, or mentions beyond what the canvas asks for.
4. **Show what's going out, then post.** Invoking the skill is the consent; the preview is for audit, not approval (unless the user asked for a dry-run):
   ```
   Channel:  #infra-reviews
   Message:  <exact text>
   ```
   `slack_send_message` with `channel_id: "C0C9Q4HNVV3"` and **no** `thread_ts` — in this channel, PRs are top-level. Report the permalink.

### bump — nudge my PRs nobody has reviewed

Uses the canvas's `bump` reaction (today `travolta`). Candidates: my top-level messages in the last 14 days (or the one PR named). Bump a message only when **all** hold:
- PR open, not draft, `reviewDecision` not `APPROVED`;
- no review reactions from anyone else on the message (`slack_get_reactions`), and `gh pr view --json reviews` shows no reviews;
- posted at least 4 working hours ago — silence must be real;
- not already carrying the bump reaction.

`slack_add_reaction` on the message carrying the PR URL. Report bumped vs skipped (with reason). The reaction *is* the bump — never post a "please review" message instead.

### merged — mark my merged PRs

Uses the canvas's `merged` reaction (today `pr-merged`). For my top-level messages in the last 14 days whose PR has `mergedAt` set and that lack that reaction: add it. Report what was marked.

### review — other people's PRs

Run [[slack-pr-review]] with:

```
--channel C0C9Q4HNVV3 --instructions F0C9PAH4TK5 [--yolo] [--watch …]
```

Everything about selection, reactions, replies, and watching is in [[slack-pr-review]]; everything about the review itself is in [[multi-agent-pr-review]]. A watch on this channel runs until stopped, or until `--until`.

## Proposed canvas addition

The canvas doesn't yet define a post format. To make `post` follow the team's format, add a section like this to the canvas (Jordan edits it; this skill never writes to the canvas):

```
# Post format
* Line 1: the PR link
* Line 2: one sentence — what it changes and why (ticket id if there is one)
* Line 3 (optional): risk / how to verify / anything the reviewer must know first
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Replied in a thread to post a PR | In this channel PRs are top-level messages. Only review conversation goes in threads. |
| Posted the same PR twice | Check the channel first; offer `bump` instead. |
| Hard-coded a format or emoji | Read the canvas every run. |
| Bumped a fresh or already-reviewed PR | Bump only on real starvation (all four conditions). |
| Posting silently | Always show the exact message as it goes out. |
