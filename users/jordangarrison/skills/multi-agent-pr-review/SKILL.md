---
name: multi-agent-pr-review
description: >-
  Use when the user asks for a thorough multi-agent review of one or more PRs.
  Takes PR URLs, checks each out in a review worktree, fans out domain
  specialists + a Rich Hickey "Simple Made Easy" lens reviewer + a George
  Fairbanks "architecturally-evident coding style" lens reviewer in parallel,
  then a consolidator that drops nits and dedupes, then posts one GitHub review
  per PR with inline comments. Attended by default (preview + 1x1 sign-off per
  PR). `--yolo` means: don't ask me, just post the review. This skill is only
  the review mechanism — it knows nothing about Slack; [[slack-pr-review]] and
  [[infra-reviews]] decide which PRs to review and signal status. Triggered by
  `/multi-agent-pr-review`, `/review-prs`, "do a multi-agent review", or
  "thorough review of <PR>".
---

# Multi-Agent PR Review

PR URLs in → review worktree → specialists + Hickey + Fairbanks → consolidator → verify → post → one result per PR out.

This skill is the **review mechanism** only. It does not read Slack, add reactions, reply in threads, or loop. Callers own those:

| Concern | Owner |
|---|---|
| How a PR is reviewed (team, prompts, gates, verdict, posting) | this skill |
| Which PRs to review, and how to tell the poster | [[slack-pr-review]] (generic), via [[infra-reviews]] or [[sre-review-thread]] |
| Repeating on a cadence | the harness scheduler, as described in [[slack-pr-review]] |
| Re-reviewing a PR I didn't approve after each new push | [[review-watch]] |

## When to Use

- User asks for a "thorough review" / "multi-agent review" of one or more PRs.
- [[slack-pr-review]] hands over the PRs it picked from a Slack channel or thread.
- A single PR that's large enough (50+ files, multi-domain) to justify multiple specialists.

**Do NOT use** for:
- Single 1-line changes — direct review is faster.
- PRs that are already merged (`mergedAt != null` → skip with a note).
- Drafts unless the user explicitly asks.

## Inputs

- One or more PR URLs (`https://github.com/<owner>/<repo>/pull/<num>`).
- Optional per-PR author note (e.g. the Slack message that posted it). Passed to every reviewer as `{AUTHOR_NOTE_OR_NONE}`.
- Optional team overrides ("skip Hickey on this one", "skip Fairbanks", "add an auth-security specialist").
- Optional `--yolo` (see below). `--skip-user-confirmation` is an accepted alias.
- Optional `--thinking <level>` (pi only): reviewer thinking level for this run, one of pi's `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Default: choose `low`, `medium`, or `high` per PR based on size, complexity, and risk, independent of the parent session's thinking level. See "Reviewer Thinking (pi)".

## `--yolo` — don't ask me, just post the review

`--yolo` means one thing: **do not ask Jordan anything. Review, then post.** No preview-for-approval, no 1x1 sign-off, no "post this?", no A/B/C verdict choice. Pick the verdict with "Verdict Selection" and post it.

| Attended (default) | `--yolo` |
|---|---|
| Preview the full review, then 1x1 sign-off per PR | **Skipped.** Build `post.json` and post. |
| Verdict offered as A/B/C per [[feedback_offer_options]] | **Decided by you** using "Verdict Selection". |
| Questions go to the user before posting | **No questions.** Anything that used to be a question goes in the report's "Needs your attention" list, after posting. |

Autonomy is not silence. After posting, report per PR: verdict, inline count, headline finding, review URL, and any "Needs your attention" items. The user is accountable for what goes out under their name and must be able to audit it.

**The human gate is gone, so the machine gates get stricter.** All mandatory under `--yolo`:

1. **Re-check `mergedAt` immediately before the fan-out**, not just at triage. PRs are routinely admin-merged within minutes of posting. If merged, skip the fan-out. See [[feedback_recheck_merged_before_fanout]].
2. **Re-fetch the PR head immediately before posting.** If `headRefOid` moved during the fan-out, read the new commits and rewrite the review against the current head — do not post findings the author already fixed. Reference the addressing commits by short SHA.
3. **Independently reproduce every finding you post inline.** Read the cited line, run the grep, check the CI run. Drop anything you cannot confirm; say in the body that you dropped it if it was load-bearing to a specialist's argument.
4. **`REQUEST_CHANGES` needs two independent confirmations** that the *diff itself* introduces the defect, not that it surfaced something pre-existing. If the two disagree, downgrade to `COMMENT` and state both readings in the body.
5. **Never `--force`, never merge, never push, never edit the PR's code.** This mode posts GitHub reviews. Nothing else.

**Cases that used to interrupt the user.** Under `--yolo` these never block the post. Post the conservative version, then put the item at the top of the report under "Needs your attention" (and in `result.json`, so a caller can surface it):
- Specialists disagree on severity and the evidence does not settle it → post the lower severity with both readings in the body.
- A finding implies live production risk needing action now, not at merge (e.g. a workload left running on divergent code against a shared queue) → post the review, flag it.
- A PR is outside what the fan-out could judge → post `COMMENT` saying what was and was not reviewed, flag it.

`--yolo` does **not** waive genuine blockers you cannot work around: missing repo clone, a PR you cannot check out, GitHub auth failure. Skip that PR, record the reason, continue with the rest.

## Run Flow (per PR)

1. **Triage** — `gh pr view <url> --json state,isDraft,mergedAt,author,headRefOid,baseRefName,title,body`. Skip merged, closed, and drafts (unless asked). Record the skip reason. **Your own PRs are reviewed like any other** — compare `author.login` to `gh api user -q .login` and, if it matches, mark the PR *self-authored*: its posted event is always `COMMENT` (see "Your Own PRs").
2. **Review worktree** — see "Review Worktrees". Cache the PR body at `/tmp/pr-review-<date>/<pr-key>/pr-body.md`.
3. **Plan the team** — derive specialists from PR domain + size (see "Team Composition"); always add Hickey and Fairbanks. In pi, inspect the diff and choose the reviewer thinking level using "Reviewer Thinking (pi)"; record the level and a one-sentence rationale in `pr-body.md`.
4. **Launch phase 1 in parallel, in the background.** One reviewer per role, each with a self-contained prompt from `reviewers/`. In Claude Code use the `Agent` tool with `run_in_background: true`; in pi use the `subagent` tool with the `pr-review.specialist` agent (lens reviewers use the same agent with the Hickey/Fairbanks template as the task) and the model from "Reviewer Thinking (pi)". Re-check `mergedAt` right before launching.
5. **Wait for completions.** Don't poll; the harness notifies on each finish.
6. **Launch the consolidator** (`reviewers/consolidator.md`; pi agent `pr-review.consolidator`, model per "Reviewer Thinking (pi)") once every phase-1 report for that PR exists.
7. **Verify** — every inline anchor is inside a diff hunk on its side (`sed -n '<line>p'` against the worktree file); every blocking claim reproduced by you (and every inline claim under `--yolo`). Specialists hallucinate occasionally; you own the published review.
8. **Re-fetch** — refresh the review ref and `gh pr view --json state,headRefOid`. If the head moved, read the new commits and rewrite.
9. **Attended only: preview, then 1x1 sign-off.** Show the full body, every inline comment (path + line + body), and the verdict — never ask "post this?" without showing it. Then accept overrides per PR (e.g. REQUEST_CHANGES → APPROVE if the issue is pre-existing). User questions during sign-off are inputs: fold them in and re-preview. *(Skipped under `--yolo`.)*
10. **Post** — `gh api -X POST /repos/<owner>/<repo>/pulls/<num>/reviews --input post.json` (see "Posting Mechanics").
11. **Record the result** — write `result.json` (see "Output Layout") and report.

## Reviewer Thinking (pi)

pi-subagents does not hand the parent's thinking level to a child: without one, the child runs at its frontmatter `thinking` (`high` in `pi-agents/`) or its own settings default. So every pi `subagent` launch here passes the level as a model suffix, which overrides frontmatter `thinking`:

1. `LEVEL` = the `--thinking` value if given; otherwise choose per PR using the table below (independent of `$PI_REASONING_LEVEL`).
2. `MODEL` = the `model:` line of the agent file pi loads: `sed -n 's/^model: //p' ~/.pi/agent/agents/pr-review-specialist.md` (or `pr-review-consolidator.md`).
3. Launch with `model: "<MODEL>:<LEVEL>"`. The full id is required: a bare `:<LEVEL>` is not a model for pi children, and the tool's `thinking` field is ignored on dispatch. In a batched `tasks` launch, pass `model` once at the top level; task items accept only `agent` and `task`.

Use the selected level for specialists, lens reviewers, and the consolidator. Automatic selection uses only `low`, `medium`, or `high`:

| Level | Review scope |
|---|---|
| `low` | Trivial, low-risk change: a one-liner or similarly small mechanical/docs edit with obvious, local effects. |
| `medium` | Mid-sized, bounded change in a familiar domain, with moderate reasoning or cross-file context needed. |
| `high` | Any large review (e.g. 50+ files, broad feature/refactor, multi-domain change), or complex/high-risk behavior regardless of diff size. |

Judge semantic scope, not line count alone: a one-line auth, permissions, secret-handling, destructive-data, or production-routing change can warrant `high`. Choose the higher level when uncertain. If later findings reveal greater complexity or risk, raise the level for remaining launches and re-review affected conclusions at that level. An explicit `--thinking` override takes precedence throughout.

If `MODEL` is empty, omit `model` and the frontmatter level applies. In Claude Code this section does not apply and `--thinking` is ignored.

## Review Worktrees

Review checkouts are detached at the PR head, so they never fight the author's branch or the main clone's state, and fork PRs work the same as same-repo PRs.

- Main clone: `~/dev/<owner>/<repo>` (the workspace folder for that org). If it is missing: attended → ask before `gh repo clone`; `--yolo` → skip the PR with reason "repo not cloned".
- Worktree path: `~/dev/<owner>/.worktrees/<repo>/pr-<num>/`.

```bash
CLONE=~/dev/<owner>/<repo>
WT=~/dev/<owner>/.worktrees/<repo>/pr-<num>
git -C "$CLONE" fetch origin --prune "+refs/pull/<num>/head:refs/remotes/origin/pr/<num>" "<base>"
if [ -d "$WT" ]; then
  git -C "$WT" status --short          # must be empty; stop on a dirty checkout
  git -C "$WT" checkout --detach origin/pr/<num>
else
  git -C "$CLONE" worktree add --detach "$WT" origin/pr/<num>
fi
for f in .env .env.local .envrc; do [ -f "$CLONE/$f" ] && cp "$CLONE/$f" "$WT/"; done
[ -f "$WT/.envrc" ] && direnv allow "$WT"
```

The diff base for reviewers is `origin/<baseRefName>`. Always run `direnv allow` after copying an `.envrc` — see [[feedback_worktree_envrc_allow]].

**Cleanup:** at the start of each run, remove `pr-<num>` worktrees this skill created whose PR is now merged or closed and whose checkout is clean (`git -C <clone> worktree remove <wt>`, then `git -C <clone> update-ref -d refs/remotes/origin/pr/<num>`). Never remove other worktrees.

## Output Layout

All artifacts go under `/tmp/pr-review-YYYY-MM-DD/<pr-key>/`. `<pr-key>` = `<repo-short>-<num>` (e.g. `audit-12`, `tf-fastly-657`).

```
/tmp/pr-review-2026-05-14/
├── audit-12/
│   ├── pr-body.md
│   ├── nestjs.md          # phase-1 specialist reports, one per role
│   ├── docker.md
│   ├── hickey.md          # lens reports
│   ├── fairbanks.md
│   ├── _final.md          # consolidator output
│   ├── post.json          # gh api payload
│   └── result.json        # what callers read
└── tf-fastly-657/...
```

`result.json` is the contract with callers such as [[slack-pr-review]]. Write it for every input PR, including skipped ones:

```json
{
  "pr": "flocasts/audit#12",
  "url": "https://github.com/flocasts/audit/pull/12",
  "status": "posted | skipped",
  "skip_reason": null,
  "verdict": "APPROVE | COMMENT | REQUEST_CHANGES",
  "review_url": "https://github.com/.../pull/12#pullrequestreview-...",
  "head_sha": "<sha the review was posted against>",
  "inline_count": 3,
  "headline": "<one line: the most important finding>",
  "needs_attention": ["<items from the --yolo list above>"]
}
```

## Reviewers

Each reviewer lives in its own file under `reviewers/`, holding its prompt template and its domain hints:

| File | Phase | Question it answers |
|---|---|---|
| `reviewers/specialist.md` | 1 | Is this lane (framework, auth, state, capacity, ...) correct? Holds the role catalog. |
| `reviewers/hickey.md` | 1 | Is the design simple? (complecting, easy vs simple, place-oriented) |
| `reviewers/fairbanks.md` | 1 | Can a reader recover the design from the code? (model-code gap, intensional rules, boundaries) |
| `reviewers/consolidator.md` | 2 | What single review should be posted? |

To add a reviewer, add a file here with its template, output path, and lane, then add it to "Team Composition".

## Team Composition

Always include Hickey, Fairbanks, and the consolidator. Scale specialists with PR size:

| PR profile | Specialists |
|---|---|
| 1-line config change | 1 (domain-fit) |
| Docs only | 1 (docs-accuracy) |
| Single-file logic | 1-2 |
| Multi-file feature, single domain | 2-3 |
| Multi-domain (e.g., NestJS + Docker + Kustomize + CI) | 4 |
| Stacked / big infra upgrade | 4-5 |

Pick specialist roles from the catalog in `reviewers/specialist.md`.

## Verdict Selection

| Verdict | Use when |
|---|---|
| `APPROVE` | No code regressions; all findings are docs polish, pre-existing, or non-blocking suggestions. **This is the default for most reviews.** |
| `COMMENT` | Substantive non-blocking concerns the author should consider but doesn't have to act on. Or for PRs you're not the canonical reviewer for. |
| `REQUEST_CHANGES` | Actual regression: bug, security gap, broken bootstrap, contract break. Reserved — most PRs that surface "concerns" still don't warrant blocking. |

If unsure between two: attended → ask the user; `--yolo` → pick the less severe one and say why in the body.

### Your Own PRs

GitHub rejects `APPROVE` and `REQUEST_CHANGES` on a PR you authored (422), but accepts `COMMENT`. So a self-authored PR gets the full review, posted as `COMMENT`:

- Run the whole flow (worktree, fan-out, consolidator, verification) as normal.
- Pick the verdict as normal, then post with `event: "COMMENT"`. Open the body with the verdict the review reached, e.g. `**Self-review — would be: APPROVE**` or `**Self-review — would be: REQUEST_CHANGES**`, so the outcome is still on the record.
- In `result.json`, `verdict` is the posted event (`COMMENT`); add `"self_authored": true` and `"intended_verdict": "<APPROVE|REQUEST_CHANGES|COMMENT>"`.
- Attended mode still previews before posting. `--yolo` posts.

## Posting Mechanics

Build the payload with `jq --rawfile` from body/comment files on disk rather than inlining markdown into a JSON string — bodies contain backticks, quotes and newlines that break hand-rolled JSON:

```bash
jq -n --rawfile body body.md --rawfile c1 c1.md \
  '{event:"APPROVE", body:$body, comments:[
     {path:"path/to/file", line:177, side:"RIGHT", body:$c1}]}' > post.json
gh api -X POST /repos/<owner>/<repo>/pulls/<num>/reviews --input post.json
```

- `line` must be in a diff hunk on the chosen `side`. `RIGHT` = new file. `LEFT` = old file (for commenting on deleted lines).
- For lines outside any hunk on a changed file: pick a different anchor line that IS in a hunk, or move the finding to the summary body.
- For files NOT in the diff at all: cannot post inline. Move to summary body.
- Multi-line comments: add `start_line`.
- If you mention "see inline comment N" in the body, the numbering refers to your `comments` array order.

## Follow-Up Reviews

When asked to re-review ("look at this one again", "check if it's addressed"), or when a caller hands over a PR you already reviewed at an older head:

1. Refresh the review ref and compare against the head you reviewed:
   ```bash
   git -C <clone> fetch origin "+refs/pull/<num>/head:refs/remotes/origin/pr/<num>"
   git -C <wt> log --oneline <old-head>..origin/pr/<num>
   git -C <wt> diff <old-head>..origin/pr/<num>
   git -C <wt> checkout --detach origin/pr/<num>
   ```
2. Map each new commit against your prior asks. Call out addressing commits by short SHA.
3. All prior asks addressed → post a fresh `APPROVE` referencing the addressing commits ("thanks for `<sha>` — the drift concern from my prior review is addressed").
4. Prior asks still open, or new asks arose from the new commits → pick the verdict with "Verdict Selection" and say which asks are still open, which commits fixed the rest, and what is new. No need to re-fan-out unless changes are large.
5. **A `COMMENT` never lifts my earlier `REQUEST_CHANGES`**: GitHub keeps the PR blocked on my last `APPROVE`/`REQUEST_CHANGES`. Once no blocker remains, post `APPROVE`, with any non-blocking findings in the same review.
6. **Recompute any quantitative claim** you made (memory headroom math, safety ratios) against the new state. If the math improved, say so — the author put work in.
7. Finish with Run Flow steps 7-11: verify, re-fetch, sign-off (attended only), post, and write `result.json` for the reviewed head.

## Special Cases

| Case | Handling |
|---|---|
| Stacked PR (based on another PR's branch) | Diff base = the parent PR's head, not `main`. Tell every reviewer: this review covers only this PR's delta. |
| Fork PR | Nothing special — `refs/pull/<num>/head` fetches fork heads too. |
| Author asked to "ignore CI failures" | Say so in the body with the root cause: "Author requested CI failures be disregarded; root cause is {reason}. Approving despite red CI." |
| PR updated mid-review, < 10 lines changed | Spot-read the new diff, post with a note. |
| PR updated mid-review, material change | Re-run the consolidator with the new state, or a mini-fan-out on just the changed files. |
| PR depends on out-of-band manual ops (runbook, state push) | Say so in the body so reviewers don't think `terraform apply` alone is enough. |

## Critical Rules

| Rule | Why |
|---|---|
| **Verify line numbers are in diff before posting** | GitHub rejects inline comments outside diff hunks. Consolidators sometimes pick line numbers that are off by one from the @@ header; spot-check against the worktree file. |
| **Independently verify blocking claims** | Specialists occasionally over-call severity; you own the published verdict. Under `--yolo`, verify every inline claim. |
| **Blocking only for actual regressions** | Pre-existing issues, docs polish, design suggestions, scope-creep observations = non-blocking. See [[feedback_pr_review_rigor]]. A Dockerfile token-leak that pre-dates the PR is *not* a regression even if the diff surfaces it. |
| **Research-first per agent** | Every specialist runs `grep` / `WebFetch` / `context7` to verify claims before asserting. No design-philosophy speculation from non-lens agents. |
| **Preview before asking to post** | Attended mode: show the full body + every inline comment + the verdict before asking. Otherwise expect "you didn't show me the review" back. **Waived by `--yolo`.** |
| **1x1 sign-off, never batch-post** | Attended mode: the user adjusts per-PR verdicts. **Waived by `--yolo`** — but still post and report per PR, not as one lump. |
| **Re-check `mergedAt` right before the fan-out** | Flo PRs get admin-merged within minutes of being posted — three floarena-api PRs merged between triage and fan-out on 2026-07-29. |
| **Re-fetch before posting** | The author may have pushed during the fan-out. Three of four findings on `ibs#920` were fixed by commits that landed mid-review. |
| **Own PRs post as `COMMENT`** | Author == current user → GitHub returns 422 on `APPROVE`/`REQUEST_CHANGES`. Review fully, post `COMMENT`, state the intended verdict at the top of the body. Never skip a PR for being yours. |
| **Drop nits in the consolidator** | Style/preference/cosmetic = drop. Hickey and Fairbanks design notes go in the summary, not inline. |
| **Autonomy is not silence** | Under `--yolo`, report every posted review after the fact. |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Inline anchored on a line that's not in the diff hunk | Re-pick an anchor inside the hunk, or fold into the summary body. |
| Skipped my own PR as "can't self-review" | Wrong. Only `APPROVE`/`REQUEST_CHANGES` are blocked. Review it and post `COMMENT`. |
| Posted REQUEST_CHANGES on docs polish | Blocking only for real regressions. Downgrade. |
| Repeated a specialist claim that CI already disproves | Check the actual workflow runs before asserting a permissions or config failure (`ibs#920`: a specialist called a leg unauthorized; CI showed all 13 legs green). |
| Asked a question under `--yolo` | `--yolo` means don't ask. Post the conservative version and list the question under "Needs your attention". |
| Consolidator keeps style/preference nits | Drop them. |
| Fairbanks agent turns into a naming-nit reviewer | A name matters only when it hides an architectural role or domain concept. Drop the rest in consolidation. |
| Skipped PR left no trace | Write `result.json` with `status: skipped` and the reason, so the caller can tell the poster. |
| Reached into Slack from here | This skill never touches Slack. Return results; the caller signals. |

## Red Flags — STOP (attended) / record in "Needs your attention" (`--yolo`)

- A PR touches secret handling and you haven't seen how secrets land in the build context — grep before approving.
- Specialists disagree on severity and the consolidator could not reconcile.
- A merged PR left something running that needs action now (a workload on divergent code against a shared queue, a role still trusted, a DNS record still live). Merging does not make the finding moot — it makes it live. A `COMMENT` review on the merged PR is the right record.

## Output Quality Bar

- Summary body: 2-4 paragraphs. Lead with the overall take. Surface the most important finding. End with a brief Hickey + Fairbanks lens paragraph.
- Inline comments: ≤ 10 per PR. Specific + actionable + ≤ 200 words each.
- No vague "consider X" without a concrete fix.
- Cite file paths + line numbers in the body; the summary must stand alone — inline comments enhance it, not replace it.
- Review bodies go out under Jordan's name: follow [[feedback_writing_as_jordan]] and [[reference_ai_smells_to_avoid]].

## Memory Touch-Points

- [[feedback_pr_review_rigor]] — research before asserting, no speculation, blocking reserved for actual regressions.
- [[feedback_offer_options]] — attended verdict choice; superseded by `--yolo`.
- [[feedback_pr_review_autopost_in_watch_mode]] — the standing authorization behind `--yolo`, and why the machine gates tighten.
- [[feedback_recheck_merged_before_fanout]] — re-check before spending agent tokens.
- [[feedback_worktree_envrc_allow]] — `direnv allow` after copying `.envrc`.
- [[feedback_writing_as_jordan]] / [[reference_ai_smells_to_avoid]] — review bodies go out under Jordan's name.
