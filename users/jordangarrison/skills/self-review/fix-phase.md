# Self-Review: Fix Phase

Runs in the author session when the watcher wakes it. Inputs from the wake: `URL`, `HEAD`, `RESULT`, `NAME`, tab id, rounds left, push mode.

## 1. Read the outcome

First match wins:

| State | Action |
|---|---|
| `status: skipped` | Report `skip_reason`, stop (step 4). |
| `status: posted` and `head_sha == HEAD` | Continue. Keep `needs_attention` for the report. |
| Anything else (`RESULT` missing, or for another head) | The reviewer stopped without a result. `herdr agent read "$NAME" --source recent-unwrapped --lines 120`, report what it says, keep the tab open, stop. |

## 2. Address the review

The fixing itself is [[pr-watch]]'s shared procedure, so a later `/pr-watch` on this PR knows what self-review already handled.

1. State file: `~/.cache/pr-watch/<owner>-<repo>-<num>.json`. If missing, create it as in [[pr-watch]] SKILL.md step 2 (`repo`, `num`, `me`, `checkout`, `handled: []`).
2. Ids: `review:<id>` (the number after `#pullrequestreview-` in `review_url`) plus `comment:<id>` for each of its inline comments: `gh api repos/<repo>/pulls/<num>/reviews/<id>/comments -q '.[].id'`.
3. Follow `~/.agents/skills/pr-watch/address.md` with that state file and those ids. With `--no-push`, tell it not to push.

If it stopped on a dirty checkout: report, keep the tab open, stop.

## 3. Next round

Rounds left, and step 2 pushed fixes → set `HEAD` to the new head, decrement rounds, and run SKILL.md steps 2, 4, and 5 again against the same agent (`NAME`). Prompt it: "Follow-up self-review of `<URL>` at head `<HEAD>`, with --yolo. Same artifact directory. When result.json is written, stop."

Otherwise finish (step 4).

## 4. Finish

Close the tab this skill created (`herdr tab close <tab-id>`) when the run ended cleanly; on any stop above, leave it open for inspection.

```
PR:        <URL>
Reviews:   <review_url per round> (would be: <intended_verdict>)
Fixed:     <n> — <sha list>
Declined:  <n> — <one line each>
Attention: <needs_attention items>
Tab:       closed | kept open (<tab-id>, reason)
```

To keep watching for other people's reviews from here, run [[pr-watch]].
