# Public privacy check

Follow the [public repository rule](../../users/jordangarrison/agents/AGENTS.md#public-repositories)
and review files, commit messages, PR text, and comments before publishing.
CI starts after content reaches GitHub. It cannot prevent the first disclosure.

## Check locally

From the repo root, with Python 3.9+, Git, and Nix:

```sh
python3 ci/privacy/check.py staged
python3 ci/privacy/check.py staged --message commit-message.txt
```

To scan staged changes and commit messages automatically, opt in to the
`commit-msg` hook. The hook runs the same credential scan. If you already have
hooks, add `python3 ci/privacy/check.py staged --hook-message "$1"` to your
existing `commit-msg` hook instead of replacing it. Local Git config is shared
by linked worktrees.

```sh
git config --local core.hooksPath .githooks
```

## What CI checks

Gitleaks scans added text lines, new commit messages, and the PR title and
body. For a PR it compares the merge base with the PR head; title and body
edits run the check again. For a push to `main` it uses the event's before and
after commits. Missing comparison commits fail the check instead of scanning
history.

The scan uses the nixpkgs revision from `flake.lock`, ignores inline
suppressions, and does not publish matches or a report. It does not scan
comments, binary files, file paths, or text added and then removed within the
same PR or push. Inspect findings locally, not in a PR or public log.

**Public privacy check** is the required status check. Review changes to the
workflow and script: a PR can change its own check.

Run the checker tests with:

```sh
python3 -m unittest discover -s ci/privacy -p 'test_*.py'
```
