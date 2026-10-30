# Discover

What [[ship]] needs to know about the workspace and the repo before it changes anything. Look each fact up; record it in the ledger.

## Workspace

From the workspace's `AGENTS.md` and its local additions file (`ADDITIONS.md` or equivalent). Where they disagree, the additions file wins.

| Fact | Where it usually lives |
|---|---|
| Tracker, team, ticket template | The additions file's project-management section; the tracker's templates |
| State map | The tracker's workflow states for the team, mapped to ship's milestones: in progress, in review, staging, production, done. Record which ones the tracker lacks |
| Branch naming | The additions file; the tracker's suggested branch for the ticket |
| Worktree convention | The router's repository conventions and [[work-dispatch]]'s selected runtime |
| Review channel skill | The additions file names it (e.g. a `/<channel> post` skill). None named → no announcement |

## Repo

| Fact | How |
|---|---|
| Checks | The repo's `CLAUDE.md`/`AGENTS.md`, then `justfile`, `Makefile`, `package.json` scripts; CI workflows show what runs on a PR |
| Merge rules | `gh api repos/<o>/<r>/rules/branches/<default>`: `pull_request` parameters (approvals, `require_code_owner_review`, `dismiss_stale_reviews_on_push`, `require_last_push_approval`, `required_review_thread_resolution`) and `required_status_checks`. Older repos: `gh api repos/<o>/<r>/branches/<default>/protection`. Owners: `CODEOWNERS` |
| Merge method | `gh api repos/<o>/<r>` (`allow_squash_merge`, …), then the style of `git log --oneline -20` on the default branch |
| Release path | How a merged change reaches each environment, and which step reaches **production**. Common shapes: merge deploys staging, and production is a separate promotion (a release PR, a tag, a manual dispatch, a GitOps sync); merge deploys production directly; nothing deploys (a library: the release is a version tag or publish). Sources: the repo's docs, workflows that run on a push to the default branch for the paths this change touches (`on.push.paths`, job `if`s on the ref), release tooling (release-please, tags), and the deploy repos it hands off to. Note each workflow's concurrency groups: a group shared with branch runs can cancel a queued deploy. When merge itself deploys production, record that: the reviewer's approval is the human look, and the merge report says it was a production release |
| Live probe | The cheapest read-only way to see the change in each environment: a describe call, a policy simulation, an endpoint, a version string. Note the credentials each needs |
