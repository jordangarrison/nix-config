---
name: sre-review-thread
description: >-
  LEGACY — delete once the team has moved to #infra-reviews. Use to review the
  PRs posted in today's "SRE Review Thread" bot thread in Flocasts
  #infra-private, usually as an unattended watch (`--watch --yolo`, every 5
  minutes) that stops when tomorrow's thread appears. Finds today's thread, then
  runs [[slack-pr-review]] in thread mode with the bot's parent message as the
  instructions. Review only; post my own PRs with [[infra-reviews]]. Triggered
  by `/sre-review-thread`, "review the SRE thread", "watch the SRE review
  thread".
---

# SRE Review Thread (legacy)

**Temporary.** Exists only until the rest of the team moves to #infra-reviews ([[infra-reviews]]). To retire: delete this directory, drop `sre-review-thread` from the `skills:` list in `../slack-pr-review/pi-agents/slack-watcher.md`, remove the [[sre-review-thread]] mentions in [[slack-pr-review]] and [[multi-agent-pr-review]], and rebuild. It is the only user of scheduled ticks: also delete `../slack-pr-review/pi-agents/slack-watcher.md` and its `agents.files` entry in `users/jordangarrison/home.nix`, and the scheduled-tick row and drift branches in [[slack-pr-review]] (steps 4 and 8, "Watching").

This skill only *locates* today's thread. Selection, reactions, replies, and watching are [[slack-pr-review]]; the review is [[multi-agent-pr-review]].

## Constants

- Channel: `#infra-private`, ID `CF7SPS45P`
- Thread parent: posted daily ~07:00 America/Chicago by the **SRE Review Thread** bot; text contains `:thread:` and `review thread`. The parent text holds the instructions (usage + reaction meanings).
- Slack mechanics: `../slack-pr-review/slack-calls.md`

## Steps

1. **Find today's thread — every pass, never from memory.** Today = `TZ=America/Chicago date +%F`. `slack_read_channel` on `CF7SPS45P`, `limit: 30`; take the latest message posted today whose text contains `review thread` (case-insensitive) and that has `:thread:` or comes from a bot. A thread_ts held from an earlier pass can belong to yesterday.
   - No match → stop: "No SRE review thread yet today (bot posts ~07:00 CT)." Under `--watch`, that pass reports it and the watch continues.
2. **Run [[slack-pr-review]]:**
   ```
   --thread CF7SPS45P <thread_ts> --instructions thread-parent [--yolo] [--watch …]
   ```
   Under `--watch`, each pass re-runs step 1 first.
3. **End condition for `--watch`:** stop when step 1 finds a thread for a newer date than the one the watch started on — that's tomorrow's thread, and this watch is done. Report the day's tally.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Reused a thread_ts across passes | Re-find today's thread every pass. A watch that crosses 07:00 CT would otherwise review yesterday's thread. |
| Posted a top-level message because no thread exists | Never. No thread → report and wait. |
| Used this to post my own PR | Post with [[infra-reviews]]; this skill is review-only. |
