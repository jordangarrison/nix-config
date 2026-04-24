---
description: Review current repository changes for correctness and risk
argument-hint: "[focus]"
---
Review the current repository changes. Focus on `$ARGUMENTS` if provided.

Use git and local inspection to check:

1. Changed files and unstaged/staged diffs.
2. Correctness and regressions.
3. Security, secrets, and unsafe filesystem behavior.
4. Nix/Home Manager evaluation risks.
5. Missing verification commands.

Report findings as:

- **Blocking**: must fix before merge
- **Non-blocking**: improvement or follow-up
- **Looks good**: areas checked with no findings

Do not modify files unless explicitly asked.
