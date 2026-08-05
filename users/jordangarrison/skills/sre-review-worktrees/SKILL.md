---
name: sre-review-worktrees
description: Use to set up the worktrees needed to review the PRs in today's SRE review thread in Flocasts #infra-private. Reads the thread, filters out the current user's own PRs and merged PRs, then creates a worktree per remaining PR at `.worktrees/<repo>/<slug>/` so [[multi-agent-pr-review]] can run against them. Triggered by `/sre-review-worktrees`, "set up worktrees for the SRE thread", or following a /sre-review post when reviewing the backlog.
---

# SRE-Review Worktree Setup

Read today's Flocasts SRE review thread → identify PRs that need review → create one worktree per PR.

This skill is **setup-only**. It does NOT post reviews. After it runs, invoke [[multi-agent-pr-review]] on the worktree list.

## When to Use

- User asks "create worktrees for each PR in the SRE thread" (skipping their own).
- After `/sre-review` posts the user's own PR — they want to review the backlog of other folks' PRs.
- `/sre-review-worktrees` is invoked.

**Do NOT use** if there's no SRE review thread today (bot may not have posted) — fall back to [[sre-review]]'s "no thread found" handling.

## Inputs

- Optional: explicit author filter (defaults to "skip Jordan Garrison's own PRs").
- Optional: PR-state filter (defaults to "open, non-merged, not already approved").
- Optional: subset selector ("only PRs from Matt", "only PRs in infra-base-services").

## Default Filters

The skill applies these filters by default. **Each filter is independent**; if any matches, the PR is dropped from the worktree fan-out.

| Filter | Why | Override |
|---|---|---|
| Author is **Jordan Garrison** | Self-review is meaningless; the user explicitly excludes their own PRs from review-cycle fan-out | `--include-self` or "include my own PRs" |
| PR is **merged** (`mergedAt != null`) | Already shipped — no need to review | `--include-merged` (rarely useful) |
| PR is **closed** (`state == "CLOSED"`) | Withdrawn — same reasoning | `--include-closed` |
| Slack reply has **`:mega-approved:` reaction** | Channel convention: at least one reviewer has already approved. Adding another review is low-value | `--include-approved` ("review even the green ones") |
| Slack reply is from a **bot** (`bot_id` set or `subtype: bot_message`) | Bot replies aren't PR submissions | (no override — always drop) |
| PR is a **draft** (`isDraft == true`) | Author isn't requesting review yet | `--include-drafts` |

PRs with `:dumpsterfire:` reaction (changes already requested) are **kept** in the fan-out by default — they often need a re-review after the author addresses. The skill should flag the existing state to the user in the preview table ("changes already requested by `<who>`") so they decide whether to add another voice.

PRs with `:reverse:` reaction ("I left a comment") are also **kept** — multiple commenters is normal in this channel.

## Overview

1. **Find today's SRE thread** — reuse [[sre-review]] cache or rescan if stale.
2. **Read thread replies** — `slack_read_thread` with the thread `ts`.
3. **Parse out PR URLs** — match `https://github.com/<owner>/<repo>/pull/<num>` (Slack-wrapped or bare).
4. **Filter** — drop the current user's own replies; drop bot replies; for each remaining PR call `gh pr view --json state,mergedAt,headRefName,headRepositoryOwner` and drop merged ones.
5. **Group by repo + present the plan** — short table shown for auditability; proceed without waiting for confirmation.
6. **For each remaining PR**: refresh the main clone, then `git worktree add`, then copy env files + `direnv allow`. Run all per-repo refreshes in parallel; run worktree creation in parallel.
7. **Report** — print the worktree paths + suggest invoking [[multi-agent-pr-review]].

## Constants

- Slack channel ID: `CF7SPS45P` (Flocasts `#infra-private`)
- SRE thread cache (managed by [[sre-review]]): `~/.claude/skills/sre-review/.cache.json`
- Workspace root: `/home/jordangarrison/dev/flocasts/`
- Worktree convention: `<workspace>/.worktrees/<repo>/<slug>/` where `slug` is the PR head branch (slashes replaced with `-`) or the ticket id.

## Steps

### 1. Find today's thread

Reuse [[sre-review]]'s exact thread detection:
- Read `~/.claude/skills/sre-review/.cache.json`. If `date` matches today (America/Chicago), use cached `thread_ts`.
- Otherwise rescan channel `CF7SPS45P` for the latest bot post containing `:thread:` and `review thread` posted today; write fresh cache.
- If no match: stop, tell the user no thread found, do not proceed.

### 2. Read thread replies

```
mcp__claude_ai_Slack__slack_read_thread
  channel_id: CF7SPS45P
  message_ts: <thread_ts>
  limit: 100
```

### 3. Parse PR URLs + apply Slack-side filters

For each reply (skip the parent message):
- **Skip if `user.name == "Jordan Garrison"`** (the workspace user). Match by name as it appears in `From: Jordan Garrison (UQ69UGHKM)` in the slack_read_thread output. Don't ship Jordan's own PRs into the worktree fan-out.
- **Skip if the message is from a bot** (`bot_id` set or `subtype: bot_message`).
- **Skip if the message has a `:mega-approved:` reaction** — the channel convention treats this as "already approved" and another review adds noise. Check the `reactions` array in the slack_read_thread output for `name == "mega-approved"` (count ≥ 1).
- Extract every match of `https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)` — most replies have exactly one. Slack wraps URLs in `<...>`; strip the angle brackets.
- If a reply has multiple PR URLs, treat them as separate PR entries from the same author (rare; usually one PR per reply per the channel rules).

**Track** which PRs were dropped by which filter so the preview table can show "skipped: 2 (Jordan), 1 (mega-approved)".

### 4. Apply GitHub-side filters

For each PR that survived step 3, run (in parallel where possible):

```bash
gh pr view <num> --repo <owner>/<repo> --json state,isDraft,mergedAt,headRefName,headRepositoryOwner,author,title,baseRefName,reviewDecision \
  -q '"\(.state) draft=\(.isDraft) mergedAt=\(.mergedAt // "null") head=\(.headRefName) base=\(.baseRefName) author=\(.author.login) review=\(.reviewDecision // "none") title=\(.title)"'
```

**Drop if:**
- `state` != `OPEN` (closed PRs).
- `mergedAt` is not null (merged PRs — surface to user with a one-line note so they know which were skipped for this reason).
- `reviewDecision` == `"APPROVED"` (formal GitHub approval already in place — same rationale as the `:mega-approved:` Slack filter; the two won't always agree, so check both).
- (Default) `isDraft` is true — drop drafts and list them in the Dropped table with reason "draft"; the user can re-run with `--include-drafts` if they want them.

**Important: the Slack-side `:mega-approved:` filter (step 3) and the GitHub-side `reviewDecision: APPROVED` filter both catch already-approved PRs but capture different signals.** A PR can have a Slack mega-approved reaction without a formal GitHub review (someone reacted but never clicked "Approve"). Drop the PR if EITHER filter matches.

Group the survivors by `<owner>/<repo>` for parallel refresh in the next step.

### 5. Present plan

Show two tables: **kept** and **dropped (with reason)**.

```
Kept:
| PR | Author | Head branch | Base | Existing state | Title |
| flocasts/audit#13 | Vijayakumar | feat-m2m-p2 | feat-m2m-p1 | dumpsterfire (changes requested) | feat(auth-phase-2): ... |
| flocasts/infra-base-services#831 | Matt | chore/document-pr-title-convention | main | reverse (1 comment) | docs(claude): ... |

Dropped:
| PR | Author | Reason |
| flocasts/web-monorepo#4156 | Jordan Garrison | your own PR |
| flocasts/infra-base-services#830 | Matt | already merged 2026-05-13 |
| flocasts/helm-charts#22 | Matt | already approved (slack :mega-approved:) |
```

The "Existing state" column surfaces Slack reactions like `:dumpsterfire:` (changes already requested) and `:reverse:` (someone commented) so the user can decide whether to add another voice. PRs with no reactions show blank.

Invoking this skill *is* the consent to create the worktrees — show the tables and proceed straight to step 6, no confirmation gate. Only pause if a Red Flag below applies or the user explicitly asked for a dry-run.

### 6. Refresh main clones + create worktrees

For each unique target repo:

```bash
cd /home/jordangarrison/dev/flocasts/<repo>

# Determine default branch
DEFAULT=$(git symbolic-ref refs/remotes/origin/HEAD --short | sed 's|origin/||')

# Check it's clean and refresh
git status --short              # bail if anything dirty
git fetch --all --prune
git checkout "$DEFAULT"
git pull --ff-only
```

Then for each PR in that repo:

```bash
WT="/home/jordangarrison/dev/flocasts/.worktrees/<repo>/<slug>"
git -C /home/jordangarrison/dev/flocasts/<repo> worktree add "$WT" <head-branch>

# Copy env files (silently skip those that don't exist)
SRC=/home/jordangarrison/dev/flocasts/<repo>
for f in .env .env.local .envrc; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$WT/" && echo "copied $f"
done
[ -f "$WT/.envrc" ] && direnv allow "$WT" && echo "direnv allow done"
```

`<slug>` rules:
- Default to the PR head branch name.
- Replace `/` with `-` (git worktree path can't contain slashes mid-component).
- Keep ticket-id-style names (`infra-6901`, `feat-m2m-p2`) verbatim where they are the head branch.

Run per-repo refresh + worktree-add in parallel where the worktrees are for different repos. Within the same repo, sequence the worktree-adds (git's worktree lock is per-repo).

### 7. Report

Print a table:

```
| PR | Worktree path | env copied | direnv allow |
| flocasts/audit#13 | .worktrees/audit/feat-m2m-p2 | (none) | (no .envrc) |
| flocasts/infra-base-services#831 | .worktrees/infra-base-services/chore-document-pr-title-convention | .envrc | done |
```

End with: "Worktrees ready. Invoke `/review-prs` or [[multi-agent-pr-review]] to start the review fan-out."

## Repo not cloned?

Check before creating the worktree:

```bash
ls -d /home/jordangarrison/dev/flocasts/<repo> 2>/dev/null
```

If the directory doesn't exist, the repo isn't cloned. Pause, ask the user:
> `<repo>` isn't cloned in the workspace. Clone it now (`gh repo clone flocasts/<repo>`)?

Wait for an answer; don't auto-clone without confirmation.

## Author already has a worktree?

If `.worktrees/<repo>/<slug>` already exists for the same branch:

- Run `git -C <repo> worktree list` and check whether the branch is already checked out somewhere.
- If yes and current: skip with a note (no action needed).
- If yes but stale (worktree HEAD ≠ PR head SHA): `git -C <wt> pull --ff-only` to refresh.
- If the directory exists but the branch differs: stop, ask the user.

## Edge cases

| Case | Handling |
|---|---|
| Fork PR (head not in `flocasts/<repo>`) | `headRepositoryOwner.login != "flocasts"` → use `gh pr checkout <num> --repo flocasts/<repo>` semantics inside the worktree, or skip with a note if your tooling can't handle forks. |
| PR head branch missing locally | `git fetch origin <head-branch>` first; if it 404s the PR may be from a fork. |
| Same head-branch name across two PRs in same repo | Slug-disambiguate with `-pr<num>` suffix (e.g., `infra-6901-pr830` and `infra-6901-pr8342` — note the second is in a *different repo* in our common case, so no real collision unless intentional). |
| Default branch is `master` vs `main` | Auto-detect via `git symbolic-ref refs/remotes/origin/HEAD`. Don't assume. |
| Dirty main clone | Don't `git pull` over uncommitted work. Stop, surface to user. |

## Composition

After this skill finishes, the natural next step is [[multi-agent-pr-review]]. Suggest it in the closing message.

If the user wants to also drop themselves a Slack mention or a status, that's [[sre-review]] territory and is separate.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Reviewing the user's own PRs | Filter by author against the current user from the start. The user's name (per memory) is `Jordan Garrison`; match against Slack reply author. |
| Creating worktrees off a stale `main`/`master` | Always `git fetch --all --prune && git checkout <default> && git pull --ff-only` first. |
| Slashes in worktree slug | Replace with `-`. `git worktree add /path/chore/foo` will fail or create unexpected nesting. |
| Forgot `direnv allow` after copying `.envrc` | Always run `direnv allow` on the new worktree dir if an `.envrc` was copied. Without it, devbox/asdf/node tooling won't activate. See [[feedback_worktree_envrc_allow]]. |
| Creating silently | No confirmation gate, but always show the kept/dropped tables before creating — the user must be able to audit what was fanned out and why. |
| Cloning a repo without asking | If a target repo isn't cloned in the workspace, ask before `gh repo clone` — the user may have a specific clone strategy. |

## Red Flags — STOP

- No SRE thread today → STOP. Don't fabricate one.
- Main clone dirty for a target repo → STOP, surface to user (their in-flight work).
- A PR points at a head ref that doesn't exist on `origin` (404 on `git fetch origin <branch>`) → STOP, may be a fork issue.
- More than 10 PRs in the thread → confirm with the user that fanning out worktrees for all of them is intentional before proceeding.

## Memory Touch-Points

- [[sre-review]] — owns thread detection + cache. This skill reuses both.
- [[multi-agent-pr-review]] — runs after this skill on the worktrees it created.
- [[feedback_worktree_envrc_allow]] — `direnv allow` discipline.
- [[feedback_worktree_discipline]] — main clone stays on default branch; use `.worktrees/<repo>/<slug>/`.
- [[using-git-worktrees]] — underlying worktree mechanics.
