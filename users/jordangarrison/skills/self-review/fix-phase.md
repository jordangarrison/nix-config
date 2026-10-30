# Self-Review: Fix Phase

Runs in the author session when the watcher wakes it. Inputs from the wake: `URL`, `HEAD`, `RESULT`, worker reference/link, rounds left, push mode, explicit thinking override (if any).

## 1. Read the outcome

If a file watch was used, consume its terminal status. Native completion events need no additional watch cleanup. Verify that the result belongs to the current run and has not already been handled.

First match wins:

| State | Action |
|---|---|
| `status: skipped` | Report `skip_reason`, stop (step 4). |
| `status: posted` and `head_sha == HEAD` | Continue. Keep `needs_attention` for the report. |
| Anything else (`RESULT` missing, or for another head) | The reviewer stopped without a result. inspect through the owning runtime, report the blocker, preserve the worker for inspection, stop. |

## 2. Address the review

The fixing itself is [[pr-watch]]'s shared procedure, so a later `/pr-watch` on this PR knows what self-review already handled.

1. State file: `~/.cache/pr-watch/<owner>-<repo>-<num>.json`. If missing, create it as in [[pr-watch]] SKILL.md step 2 (`repo`, `num`, `me`, `checkout`, `handled: []`).
2. Ids: `review:<id>` (the number after `#pullrequestreview-` in `review_url`) plus `comment:<id>` for each of its inline comments: `gh api repos/<repo>/pulls/<num>/reviews/<id>/comments -q '.[].id'`.
3. Follow `~/.agents/skills/pr-watch/address.md` with that state file and those ids. With `--no-push`, tell it not to push.

If it stopped on a dirty checkout: report, preserve the worker, stop.

## 3. Next round

Rounds left, and step 2 pushed fixes → set `HEAD` to the new head, decrement rounds, and run SKILL.md steps 2–5 again. Use a new reviewer or supported continuation as the runtime requires. Prompt it: "Follow-up self-review of `<URL>` at head `<HEAD>`, with --yolo. Same artifact directory. When result.json is written, stop." In pi, include the user's explicit `--thinking <level>` override if supplied; otherwise let the review engine reassess child-agent thinking for the new diff.

Otherwise finish (step 4).

## 4. Finish

Use the owning runtime to clean up disposable reviewer resources this skill created when the run ended cleanly. Preserve dedicated threads unless cleanup was authorized; on blockers keep the worker available for inspection.

```
PR:        <URL>
Reviews:   <review_url per round> (would be: <intended_verdict>)
Fixed:     <n> — <sha list>
Declined:  <n> — <one line each>
Attention: <needs_attention items>
Worker:    <link/reference> — completed | retained | cleaned up (reason)
```

To keep watching for other people's reviews from here, run [[pr-watch]].
