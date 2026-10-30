# Land, release, close

Stages 4–6 of [[ship]]: from an approved PR to production and a closed ticket, with Jordan's go between the two.

## 4. Land (the default stop)

1. **Preconditions.** All must hold, per the merge rules in the ledger:
   - the required approvals, including code owners, on the current head. Approval comes from a person other than Jordan's own sessions; ship never approves;
   - required checks green;
   - every review thread resolved (resolve your own after replying; someone else's only after their item is answered);
   - not a draft.

   Merging is blocked? `gh pr view --json mergeStateStatus,reviewDecision` plus the review threads (GraphQL `reviewThreads`) name the cause. `UNSTABLE` means only a non-required check is pending, so merging can go ahead.
2. **Merge** with the method the repo allows and its history uses. For a stack: `gh stack merge <pr> --yes --<method>`, then `gh stack sync`, and confirm with `git range-diff` that the layers above are unchanged. `--admin` only on Jordan's explicit say.
3. **Follow what the merge set off.** Find the runs on the default branch for the merge commit (the ledger's release path), and watch each one by run id.
   - **Cancelled:** find why. A newer pending run in a shared concurrency group replaces the older one. Re-run it, and hold every push to the repo until it is in progress.
   - **Failed:** read the failed log, diagnose, and report before touching anything.
4. **Verify on staging** with the ledger's probe: green CI shows the pipeline ran, the probe shows the change took. Record what it returned. Move the ticket to its staging state.

   **When merge deploys production** (the release path says so), steps 3–4 are the production release and its verification. The reviewer's approval was the human look. Say so in the merge milestone, move the ticket to its production state, and go on to **6. Close**.
5. **Clean up the code side:** the worktree and branches, per *Clean up* below. The ticket, the ledger and any release watchers stay until the run closes.

Done when the change is verified on staging, or in production for merge-deploys-production repos. With the default `--to land`, end here with the release question: what's in it, how it checked out on staging, and the exact release step you would take.

## 5. Release (Jordan's go)

Only after Jordan says go: `--to close` at invocation counts as go for this one change.

1. **Release** by the ledger's production step: promote the build, merge the release PR, push the tag, dispatch the prod workflow, or sync. Releases that bundle other people's changes (a release PR, a shared train) get the bundle listed in the release question first.
2. **Follow and verify in production** exactly as in steps 3–4, with the production probe. Move the ticket to its production state.

Done when the production probe shows the change.

## 6. Close

1. **Review channel:** add its merged marker to the PR's post (at the merge, without waiting for the release).
2. **Ticket:**
   - Comment with what shipped (PR, merge commit, release), how to use it if anyone has to, and any follow-ups.
   - A comment that asks or tells other people things goes through the preview gate in [[ship]]'s *Engaging Jordan*.
   - Move the ticket to the tracker's done state.
3. **Clean up** whatever is left, and the ledger last.

Done when nothing the ledger listed is still live.

## Clean up

Only what this run created:

- **Worktree and its workspace:** use the owning runtime's cleanup operation; raw `git worktree remove` only for manually managed checkouts. Generated untracked files (a lockfile) can go; anything else, ask first.
- **Local branches:** `git branch -D`, after `git diff origin/<default> <branch>` shows its content is on the default branch. Squash merges make branches look unmerged to git.
- **The rest:** stack metadata, [[pr-watch]] state files, reviewer tabs, every watcher in the ledger, and scratch branches. Keep runs that evidence cites.

## Report

```
Shipped:    <ticket> via <PR(s)> → <merge sha(s)>
Staging:    <probe and what it returned>, or "merge deploys production"
Production: <release step and probe result>, or "waiting on your go: <exact step>"
Ticket:     <state>, <channel marker>
Cleaned:    <worktree, branches, watchers>
Follow-ups: <one line each, or none>
```

Follow-ups stay a list. File tickets for them only when Jordan asks.
