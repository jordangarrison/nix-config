#!/usr/bin/env bash
# pr-watch gate. Side-effect free: reads GitHub and the state file, writes nothing.
#
#   check.sh <state-file>
#
# Exit 0 (wake) when the PR is no longer open, or when it has feedback whose id
# is not in .handled. Exit 1 otherwise,
# including on any lookup failure (fail closed: the next interval retries).
# Prints the reason and any unhandled ids on stdout.
set -uo pipefail

state=$1
repo=$(jq -er .repo "$state") || exit 1
num=$(jq -er .num "$state") || exit 1
me=$(jq -er .me "$state") || exit 1

pr_state=$(gh pr view "$num" -R "$repo" --json state -q .state) || exit 1
if [ "$pr_state" != OPEN ]; then
  echo "pr:$pr_state"
  exit 0
fi

# Feedback = every submitted review (anyone, me included: self-review posts as me),
# every top-level inline comment, and replies / PR comments from other people.
# My own replies and PR comments are my answers, not feedback. Bot PR comments
# (Linear, CI) are noise; bot reviews are kept.
reviews=$(gh api --paginate "repos/$repo/pulls/$num/reviews" \
  | jq -r '.[] | select(.state != "PENDING")
           | select(.state != "COMMENTED" or ((.body // "") != ""))
           | "review:\(.id)"') || exit 1
inline=$(gh api --paginate "repos/$repo/pulls/$num/comments" \
  | jq -r --arg me "$me" '.[] | select(.in_reply_to_id == null or .user.login != $me)
                          | "comment:\(.id)"') || exit 1
issue=$(gh api --paginate "repos/$repo/issues/$num/comments" \
  | jq -r --arg me "$me" '.[] | select(.user.login != $me and .user.type != "Bot")
                          | "issue:\(.id)"') || exit 1

unhandled=$(printf '%s\n' $reviews $inline $issue \
  | jq -R . | jq -rs --slurpfile s "$state" '. - ($s[0].handled // []) | .[]')
if [ -n "$unhandled" ]; then
  echo "feedback:"
  echo "$unhandled"
  exit 0
fi

exit 1
