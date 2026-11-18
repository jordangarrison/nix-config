- I use nix, you can use nix run and nix shell if a tool is not available in my environment
- use conventional commits
- put the ticket number in the commit message if it's relevant
- NEVER force push (no --force, no -f, no --force-with-lease). Always push normally.
  - Exception: stacked PR branches (a branch whose PR is based on another open PR's branch). Rebasing + force-pushing stacked branches during stack sync is expected and allowed there — do not merge the base branch into a stacked branch; restack instead. Use the `gh stack` CLI extension for this, but only if it's installed (check with `gh stack --help`) AND the repo has GitHub's Stacked PRs feature enabled (`gh stack link` exits with code 9 if not). If either is missing, fall back to plain git: stacked PRs via `gh pr create --base <parent-branch>`, synced by rebasing onto the parent + force-pushing the stacked branch, retargeting to main after the parent merges.
- If available use @.github/PULL_REQUEST_TEMPLATE.md when making pull requests
- Give me times in my local timezone
- Ideology
  - Follow principles conveyed on https://grugbrain.dev
  - Rich Hickey's "Simple Made Easy" is the design philosophy for what we're doing
  - Write in George Fairbanks' "architecturally evident coding style" from Just Enough Software Architecture
- Try to use ASD-STE100 unless more complex language is required and pretend I have ADHD


## Public repositories

In public repositories and repos intended for publication, keep these out of files, fixtures, commits, PRs, and comments:

- Secrets: keys, tokens, and passwords.
- Company endpoints that need no login, and how to reach them.
- Security details someone could use against the company, such as exact firewall rules or ways around them.
- Customer data and people's personal data.

Internal URLs and hostnames, ticket and incident IDs, Slack IDs, teammates' names, timings and counts, and the owner's own non-secret config values (such as account names) are fine on their own.
