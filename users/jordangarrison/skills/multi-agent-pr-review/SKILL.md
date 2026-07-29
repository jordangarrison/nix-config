---
name: multi-agent-pr-review
description: Use when the user asks to do a thorough multi-agent review of one or more PRs (or every non-author PR in the daily SRE review thread). Fans out domain specialists + a Rich Hickey "Simple Made Easy" lens reviewer in parallel background, then a consolidator that drops nits and dedupes findings, then 1x1 sign-off per PR before posting via gh api with inline comments. When thread-driven, signals status to the poster via Slack reactions (eye-twitch on launch; mega-approved / reverse / dumpsterfire mirroring the posted verdict). Triggered by `/review-prs`, "do a multi-agent review", "review the SRE thread PRs", or following a /sre-review thread fan-out.
---

# Multi-Agent PR Review

Domain specialists + Hickey lens + consolidator → 1x1 sign-off → `gh api` post with inline comments.

## When to Use

- User asks for a "thorough review" / "multi-agent review" / "review all PRs in the thread".
- After `/sre-review` to review the PRs in today's thread (skip the user's own PRs).
- Reviewing 2+ PRs in one cycle where parallel fan-out saves time.
- A single PR that's large enough (50+ files, multi-domain) to justify multiple specialists.

**Do NOT use** for:
- Single 1-line changes — direct review is faster.
- PRs that are already merged (`mergedAt != null` → skip with a note).
- Drafts unless the user explicitly asks.

## Inputs

Skill accepts:
- One or more PR URLs (`https://github.com/<owner>/<repo>/pull/<num>`).
- "the SRE thread" / "today's review thread" → read with the [[sre-review]] thread mechanics, then operate on every reply that isn't the current user and isn't already merged.
- Optional: domain hint to override the auto-derived team (e.g., "skip the Hickey agent on this one", "add an auth-security specialist").

## Slack Reaction Signaling

When the review is driven off the daily SRE thread (the common case via [[sre-review-worktrees]]), signal review status back to the PR poster by reacting on **their thread reply** — the Slack message that carries the PR URL. This is the channel's native convention (the same reactions [[sre-review-worktrees]] *reads* to filter the fan-out; here we *write* them).

Constants:
- Channel ID: `CF7SPS45P` (Flocasts `#infra-private`)
- SRE thread cache: `~/.claude/skills/sre-review/.cache.json` (managed by [[sre-review]])
- Tool: `mcp__claude_ai_Slack__slack_add_reaction` (emoji name **without** colons; adding a duplicate succeeds silently)

Reaction vocabulary (emoji → meaning → when the reviewer adds it):

| Reaction | Meaning to the poster | When to add |
|---|---|---|
| `eye-twitch` | "I'm reviewing your PR" | At **phase-1 launch** for that PR — tells the poster someone picked it up |
| `mega-approved` | "Approved" | After posting an `APPROVE` review |
| `reverse` | "I left a comment" | After posting a `COMMENT` review |
| `dumpsterfire` (optionally also `pepehands`) | "Review requested changes / declined" | After posting a `REQUEST_CHANGES` review |
| `travolta` | "this PR isn't getting the love it deserves — bump" | **Poster-side nudge, not used by the reviewer.** Listed for vocabulary completeness; never auto-add it during a review. |

Rules:
- **Only react when thread-driven.** For ad-hoc PR URLs passed directly (not in today's thread), skip reactions entirely — there's no message to react to. Don't post a new Slack message as a substitute.
- **Resolve the message `ts` per PR.** Read today's thread (`slack_read_thread` on the cached `thread_ts`, channel `CF7SPS45P`) and match each PR URL to the reply that contains it. Keep a `pr-key → message_ts` map. If a PR URL has no matching reply, skip reactions for that PR.
- **The verdict reaction mirrors the posted GitHub review** — add it as part of the post step (step 10), after the user has signed off on the verdict. It's the same decision the user already approved, so no separate confirmation is needed. `eye-twitch` is benign and goes on at launch without a prompt.
- **One verdict reaction per review.** Don't stack `mega-approved` + `dumpsterfire` on the same message. The `eye-twitch` (in-progress) reaction may coexist with the final verdict reaction — leave it; the verdict reaction is the signal that supersedes it.

## Overview (per PR)

1. **Worktree setup** — fetch, refresh default branch, `git worktree add` at `.worktrees/<repo>/<slug>/`, copy env files, `direnv allow`. (For the multi-PR case driven off the daily SRE thread, [[sre-review-worktrees]] does this end-to-end and lands you here with worktrees already created.)
2. **Plan the team** — derive role list from PR domain + size; always include a Hickey lens reviewer.
3. **Launch phase 1** in parallel via `Agent` tool with `run_in_background: true`. Each agent gets a self-contained prompt and writes its report to `/tmp/sre-review-YYYY-MM-DD/<pr-key>/<role>.md`. **If thread-driven, add the `eye-twitch` reaction** to the PR's Slack reply now (see "Slack Reaction Signaling") so the poster knows the review is underway.
4. **Wait for completions.** Don't poll; the harness notifies on each finish.
5. **Launch consolidator** once all phase-1 agents for that PR are done. It reads every `<role>.md`, drops nits aggressively, dedupes, writes `_final.md` with verdict + summary body + inline-comments array.
6. **Verify line numbers** are inside diff hunks before posting (GitHub rejects inline comments outside hunks; for files not in the diff, fold the finding into the summary body).
7. **Verify any blocking claim independently** — before posting REQUEST_CHANGES on a specialist's call, the parent should reproduce the evidence (grep the file, read the cited line, run the build, etc.). Specialists hallucinate occasionally; you own the published review.
8. **Preview to the user before asking to post** — show the full proposed body, the full inline-comment list (path + line + body), and the verdict. Do not ask "post this?" without showing it. The user said "you didn't show me the review" once during the conversation that produced this skill — that's the failure mode this rule prevents.
9. **1x1 sign-off per PR** — show the user verdict + summary + inline count + headline finding; accept overrides (e.g., REQUEST_CHANGES → APPROVE if the issue is pre-existing). User questions during sign-off (e.g., "should we also recommend removing X?") may add a new inline or summary paragraph — fold them in and re-preview before posting.
10. **Post** with `gh api -X POST /repos/<owner>/<repo>/pulls/<num>/reviews --input <file>.json`. **Then, if thread-driven, add the verdict reaction** to the PR's Slack reply (`APPROVE` → `mega-approved`, `COMMENT` → `reverse`, `REQUEST_CHANGES` → `dumpsterfire`). This mirrors the verdict the user just signed off on.

## Output Layout

All artifacts go under `/tmp/sre-review-YYYY-MM-DD/<pr-key>/`:

```
/tmp/sre-review-2026-05-14/
├── audit-12/
│   ├── nestjs.md          # phase-1 role output
│   ├── docker.md
│   ├── kustomize.md
│   ├── ci.md
│   ├── hickey.md
│   ├── _final.md          # consolidator output
│   └── post.json          # gh api payload
├── audit-13/...
└── tf-fastly-657/...
```

`<pr-key>` = `<repo-short>-<num>` (e.g., `audit-12`, `tf-fastly-657`). Pick a sensible short form.

See `agent-prompts.md` for the full prompt templates and the consolidator prompt.

## Team Composition

Always include a Hickey reviewer and a consolidator. Scale specialists with PR size:

| PR profile | Specialists |
|---|---|
| 1-line config change | 1 (domain-fit) |
| Docs only | 1 (docs-accuracy) |
| Single-file logic | 1-2 |
| Multi-file feature, single domain | 2-3 |
| Multi-domain (e.g., NestJS + Docker + Kustomize + CI) | 4 |
| Stacked / big infra upgrade | 4-5 |

Roles to pick from (by domain):

- **Code-heavy** (NestJS/Phoenix/Rails/Express): framework-arch, auth-security, type-system, tests, db-migrations.
- **Infra / Terraform**: tf-upgrade, provider-specific (e.g. fastly-provider), state-migration, repo-hygiene, secrets/CI.
- **Helm / K8s**: helm-template, k8s-integration, resource-limits.
- **Frontend**: react-arch, a11y, perf, tests.
- **Docs**: docs-accuracy (verify against the ground truth — workflow file, spec, etc.).
- **SRE / capacity**: sre-capacity (memory/CPU/HPA math), runbook-accuracy.

The Hickey reviewer is always domain-independent — it evaluates complecting, easy-vs-simple, place-oriented programming, single source of truth.

## Critical Rules

| Rule | Why |
|---|---|
| **Verify line numbers are in diff before posting** | GitHub rejects inline comments outside diff hunks. For files NOT in the diff, fold the finding into the summary body — don't pretend it's inline. Consolidators sometimes pick line numbers that aren't in the hunk (off-by-one from the @@ header); always spot-check with `sed -n '<line>p' <file>` against the new file in the worktree. |
| **Independently verify blocking claims** | Before posting `REQUEST_CHANGES` on a specialist's finding, reproduce the evidence yourself (read the cited file, grep for the contradiction, run a quick build). Specialists occasionally over-call severity; you own the published verdict. |
| **Blocking only for actual regressions** | Pre-existing issues, docs polish, design suggestions, scope-creep observations = non-blocking. See user memory `feedback_pr_review_rigor`. Downgrade REQUEST_CHANGES → COMMENT or APPROVE if the issue is pre-existing or out-of-scope. Specifically: a Dockerfile token-leak that pre-dates this PR is *not* a regression even if surfaced by the diff. |
| **Research-first per agent** | Every specialist runs `grep` / `WebFetch` / `context7` to verify claims before asserting. No Hickey-style speculation from non-Hickey agents. |
| **Preview before asking to post** | Show the user the full proposed body + every inline comment (path, line, body) + the verdict. If you ask "post this?" without showing them first, expect "you didn't show me the review" back. |
| **1x1 sign-off, never batch-post** | User adjusts per-PR verdict; never auto-post all 5 at once. GitHub review posts are visible and disruptive to other reviewers. |
| **Re-fetch before posting** | `git fetch origin <branch>` and `gh pr view --json state,headRefOid` right before building the post — the author may have pushed addressing comments in the time it took the agents to run. Stale reviews look bad. The specific case to anticipate: a `docs(...)` commit landing during the fan-out that addresses your main concern (we saw this with the AGENTS.md drift in `ibs#831`). |
| **Skip merged PRs** | `gh pr view --json mergedAt` → if not null, skip and report to user. PRs can merge during the fan-out — re-check at post time too. |
| **Don't self-approve** | If `gh pr view --json author` matches the current user, GitHub returns 422. Filter before fan-out. |
| **Drop nits in the consolidator** | The user explicitly said dump nits. Style/preference/cosmetic = drop. Keep only correctness/security/regression/material design risk. Hickey design notes go in summary, not inline. |
| **User mid-flight adjustments are inputs, not interruptions** | When the user asks during sign-off "should we also flag X?" or "is this really a regression?", treat their question as a signal to adjust the review (add inline, change verdict, fold context). Re-preview after each adjustment. |
| **React on the poster's reply, mirror the posted verdict** | When thread-driven: `eye-twitch` at launch, then the verdict reaction (`mega-approved`/`reverse`/`dumpsterfire`) after posting. Never add `travolta` (that's a poster-side bump, not a review signal). Never react in place of posting the GitHub review, and never react when the PR was passed as a bare URL not in today's thread. See "Slack Reaction Signaling". |

## Verdict Selection

| Verdict | Use when |
|---|---|
| `APPROVE` | No code regressions; all findings are docs polish, pre-existing, or non-blocking suggestions. **This is the default for most reviews.** |
| `COMMENT` | Substantive non-blocking concerns the author should consider but doesn't have to act on. Or for PRs you're not the canonical reviewer for. |
| `REQUEST_CHANGES` | Actual regression: bug, security gap, broken bootstrap, contract break. Reserved — most PRs that surface "concerns" still don't warrant blocking. |

If unsure between two: ask the user.

## Posting Mechanics

Build a JSON file per PR at `/tmp/sre-review-YYYY-MM-DD/<pr-key>/post.json`:

```json
{
  "event": "APPROVE | COMMENT | REQUEST_CHANGES",
  "body": "...summary markdown...",
  "comments": [
    {
      "path": "file/path",
      "line": 123,
      "side": "RIGHT",
      "body": "..."
    }
  ]
}
```

Notes:
- `line` must be in a diff hunk on the chosen `side`. `RIGHT` = new file. `LEFT` = old file (for commenting on deleted lines).
- For lines outside any hunk on a changed file: pick a different anchor line that IS in a hunk, or move the finding to the summary body.
- For files NOT in the diff at all: cannot post inline. Move to summary body.
- Multi-line comments: add `start_line`.
- If you mention "see inline comment N" in the body, the numbering refers to your `comments` array order on GitHub's rendered review.

Post:

```bash
gh api -X POST /repos/<owner>/<repo>/pulls/<num>/reviews --input post.json
```

## Follow-Up Reviews

When the user says "look at this one again" / "rereview this one" / "check if it's addressed":

1. `git fetch origin <branch>` and check `origin/<branch>` vs the HEAD you reviewed.
   ```bash
   git -C <worktree> fetch origin <branch>
   git -C <worktree> rev-list --left-right --count HEAD...origin/<branch>
   git -C <worktree> log --oneline origin/<branch> -5
   ```
2. Pull and read the new diff between the reviewed HEAD and current HEAD:
   ```bash
   git -C <worktree> log --oneline <old-head>..origin/<branch>
   git -C <worktree> diff <old-head>..origin/<branch>
   ```
3. Map each new commit against your prior asks. If a commit's message clearly addresses an ask (e.g., `docs(agents): sync AGENTS.md with CLAUDE.md` addressing the drift ask), call that out by SHA in the follow-up body.
4. If your prior asks are all addressed → post a fresh `APPROVE` referencing the addressing commits by short SHA. Body should explicitly say "thanks for `<sha>` — drift concern from my prior review is addressed."
5. If new asks arose from the new commits → post a `COMMENT` with the new findings; no need to re-fan-out unless changes are large.
6. **Recompute any quantitative claim** you made (e.g., memory headroom math, safety ratios) against the new state. If the math improved, say so explicitly — the author put work in.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Inline anchored on a line that's not in the diff hunk | Re-pick anchor line inside the hunk, or fold into summary body. |
| `event: APPROVE` on your own PR | GitHub returns 422. Check author first. |
| Posted REQUEST_CHANGES on docs polish | Memory rule: blocking only for real regressions. Downgrade. |
| Forgot to skip merged PRs | Check `mergedAt` upfront, drop them from the fan-out. |
| Stale review (author pushed during fan-out) | Re-fetch before building `post.json`; if HEAD moved, re-read the diff and possibly re-run consolidator with the latest state. |
| Consolidator keeps style/preference nits | Drop them. User explicitly said dump nits. Hickey design notes go to summary, not inline. |
| Used Slack to broadcast a review status | This skill posts via GitHub PR review API only. The only Slack write it does is the status **reaction** on the poster's thread reply (`eye-twitch` / `mega-approved` / `reverse` / `dumpsterfire`). For SRE-thread message posting, the [[sre-review]] skill handles that separately. |
| Verdict reaction doesn't match the posted review | The reaction must mirror the GitHub verdict exactly: `APPROVE`→`mega-approved`, `COMMENT`→`reverse`, `REQUEST_CHANGES`→`dumpsterfire`. Re-pick if you downgraded the verdict during sign-off. |
| Stacked `mega-approved` + `dumpsterfire` on one reply | One verdict reaction per review. The `eye-twitch` may coexist with the verdict; the two verdict reactions must not. |
| Reacted on the wrong message | Reactions go on the poster's **thread reply** (the message carrying the PR URL), not the bot's parent thread message. Resolve `pr-key → message_ts` from the thread before reacting. |

## Red Flags — STOP

- Author asked to "ignore CI failures" — that's OK, but document the failure rationale in the body so future readers know why it was approved over red CI.
- The PR depends on out-of-band manual ops (a runbook, an S3 state push) — note that explicitly in the body so reviewers don't think `terraform apply` alone is sufficient.
- Reviewing a PR that touches secret-handling without seeing how secrets land in the build context — pause and grep before approving.
- Specialist agents disagree on severity — the consolidator should reconcile, but surface the disagreement to the user instead of silently picking one side.

## Memory Touch-Points

This skill complements:
- [[sre-review]] — posts the user's own PR link to today's `#infra-private` thread (one-way: user → thread).
- [[sre-review-worktrees]] — reads the same thread the other direction (thread → worktree fan-out), filtering out the user's own PRs and already-approved ones. This is the natural setup step before invoking the present skill on multi-PR batches.
- [[dispatching-parallel-agents]] — the underlying parallel-agent mechanics.
- [[feedback_pr_review_rigor]] — the rule "research before asserting, no Hickey speculation, blocking reserved for actual regressions" lives here.
- [[feedback_offer_options]] — verdict choice is one of those costly/irreversible decisions; offer A/B/C.
- [[using-git-worktrees]] — worktree setup convention.
- [[feedback_worktree_envrc_allow]] — `direnv allow` discipline after copying `.envrc` into a new worktree.

## End-to-End Composition

```
1. /sre-review                  → posts user's own PR to today's thread
2. /sre-review-worktrees        → reads thread, filters Jordan + merged + mega-approved,
                                  creates worktrees for the rest
3. /review-prs  (this skill)    → fans out specialists + Hickey + consolidator per PR,
                                  reacts eye-twitch on launch, 1x1 sign-off, posts via gh api,
                                  reacts verdict (mega-approved / reverse / dumpsterfire) on the thread reply
4. /loop optionally             → if reviews come in waves, repeat 2-3 across the day
```

## Output Quality Bar

- Summary body: 2-4 paragraphs. Lead with overall take. Surface the most important finding. End with brief Hickey lens.
- Inline comments: ≤ 10 per PR. Specific + actionable + ≤ 200 words each.
- No vague "consider X" without a concrete fix.
- Cite line numbers + file paths in body so the reader can navigate. The summary should be self-contained — the inline comments enhance, not replace, the body.
