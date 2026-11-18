# Public privacy check

Review files, commit messages, PR text, and comments before publishing. The
checker is a backup, not a substitute for review. GitHub Actions starts after
content reaches GitHub; it cannot prevent the first disclosure.

## Check locally before publishing

From the repository root, with Python 3.9+ and Git:

```sh
python3 ci/privacy/check.py staged
python3 ci/privacy/check.py staged --message commit-message.txt
```

To check each proposed commit message and its staged changes automatically, opt
in to the `commit-msg` hook. Do not replace existing hooks; if you already have
hooks, run the checker from your current `commit-msg` hook instead. Local Git
config is shared by linked worktrees.

```sh
git config --local core.hooksPath .githooks
```

Add `--gitleaks` to a manual check to also scan new text with Nix and Gitleaks.
The hook does not require Nix. For private patterns, set `PRIVACY_PATTERNS` from
an untracked private file in your local shell; do not paste its contents into a
command line or public record.

## CI scope

- PRs (including title/body edits): added lines from the merge base to the PR
  head, commit messages not on the base, and the event's PR title and body.
- Pushes to `main`: added lines and new commit messages between the event's
  before and after commits. Missing endpoints fail rather than scanning history.
- Gitleaks reads added text only. It does not receive file paths; path-based
  rules do not apply. Neither scan covers binary attachments, and the workflow
  does not inspect comments, PR edit history, or arbitrary names and customer data.
- Findings do not print matched text. The Gitleaks result is intentionally
  generic; inspect it locally, not in a public log or comment.

After the workflow is active on `main`, require **Public privacy check** in the
branch ruleset to block merging a PR that fails it. Review changes to this
workflow, its checker, and the allowlist: a PR can modify its own workflow.

## Optional repository variable

In **Settings → Secrets and variables → Actions → Variables**, add a repository
variable named `PRIVACY_PATTERNS`. Use one Python regular expression per line;
blank lines and `#` comments are ignored. Use only patterns safe for the public
runner and its logs. Actions variables are not secrets. Keep confidential
hostnames and other sensitive values in the local-only pattern file instead.
Built-in checks always run, including on forks without the variable. No secrets
are needed.

## Synthetic fixtures

Use ordinary synthetic text unless a test must match a blocked pattern. Each
exception in [`allowlist.tsv`](allowlist.tsv) binds one repo-relative path to the
SHA-256 of one exact synthetic line, without the newline, separated by a tab.
Compute the digest with `printf '%s' "$synthetic_line" | sha256sum`. Never
allowlist live data. Exceptions do not affect commit messages, PR text, or
Gitleaks. Run the checker tests with:

```sh
python3 -m unittest discover -s ci/privacy -p 'test_*.py'
```
