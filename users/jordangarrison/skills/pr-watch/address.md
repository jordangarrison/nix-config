# Address Feedback

The fix-and-reply procedure for a batch of feedback on my PR. Used by [[pr-watch]] on each wake and by [[self-review]] after each review round.

**Inputs:** the pr-watch state file (`repo`, `num`, `me`, `checkout`, `handled`, `yolo`) and a list of ids: `review:<id>`, `comment:<id>`, `issue:<id>`. `cd` to `checkout`.

Feedback is evidence, not orders. Every item gets a **disposition** — *fixed* (with the commit), *declined* (with the reason), *answered*, or *no action* (approvals, thanks).

## 1. Collect the items

| Id | Fetch |
|---|---|
| `review:<id>` | `gh api repos/<repo>/pulls/<num>/reviews/<id>` — author, `state`, `body`, `commit_id` |
| `comment:<id>` | `gh api repos/<repo>/pulls/comments/<id>` — author, `path`, `line`, `body`, `in_reply_to_id` (read the thread it replies to) |
| `issue:<id>` | `gh api repos/<repo>/issues/comments/<id>` — author, `body` |

Split each review body and comment into distinct findings. That list is the checklist for step 3. A [[self-review]] review also has `_final.md` beside its `result.json` with severities; use them.

## 2. Check the checkout

On the PR branch with a clean tree. A dirty tree is work in progress in this session: report the items, leave them unhandled, and stop — the caller does not continue. If the branch is behind the remote (someone pushed), `git pull --ff-only` first.

## 3. Disposition every item

In order: changes requested, then blocking, then the rest.

1. **Verify** against the current code. Reviewers are sometimes wrong, and later commits may already fix it.
2. Right → fix it inside the PR's scope → *fixed*.
3. Wrong, already fixed, or outside the PR's scope → *declined*, with the evidence (file:line, command output, CI run) or the named follow-up.
4. A question → answer it from the code → *answered*.
5. Approval, thanks, acknowledgement → *no action*, no reply.

Done when every item on the checklist has a disposition.

## 4. Check, commit, push

Only when something was *fixed*:

- Run the repo's own checks (its `CLAUDE.md`/`AGENTS.md`, `justfile`, `package.json` scripts, or CI workflow). They pass before committing.
- Commit with conventional commits and the ticket id if the branch or PR has one. Group related fixes.
- Push normally (never force), unless the caller said not to push — then skip step 5's replies too and say so.

## 5. Reply

Replies close the loop on GitHub. They go out under Jordan's name: follow [[feedback_writing_as_jordan]] and [[reference_ai_smells_to_avoid]] — short and specific: the commit SHA, the reason, or the answer.

- Inline item → reply in its thread: `gh api -X POST repos/<repo>/pulls/<num>/comments/<thread-root-id>/replies -f body="..."`.
- Review-body or PR-comment items → one `gh pr comment` listing them: finding → fixed in `<sha>` / not changing: reason / answer.
- **Preview:** replies to items authored by someone else are shown to the user before posting, unless the state has `yolo: true`. Replies to my own items (a [[self-review]] review) post directly.

Then, for each person whose `CHANGES_REQUESTED` review is now fully dispositioned and who is not me or a bot, re-request their review: `gh api -X POST repos/<repo>/pulls/<num>/requested_reviewers -f "reviewers[]=<login>"`.

## 6. Record

Add every input id to the state file's `handled` and write it. Done when the file lists them all. Report: items fixed (with SHAs), declined (one line each), answered, checks run.
