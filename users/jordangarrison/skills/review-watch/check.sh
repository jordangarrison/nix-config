#!/usr/bin/env bash
# review-watch gate. Side-effect free: reads GitHub and the state file, writes nothing.
#
#   check.sh <state-file>
#
# Exit 0 (wake) and print the reason, first match wins:
#   pr:MERGED | pr:CLOSED   the PR is no longer open
#   approved                my latest verdict review is an approval, whoever posted it
#   head:<seen>..<head>     the head moved past .seen_head and the PR is not a draft
#   quiet                   no new commit for .quiet_hours (counted from arming at the earliest)
# Exit 1 otherwise, including on any lookup failure (fail closed: the next tick retries).
set -uo pipefail

state=$1
repo=$(jq -er .repo "$state") || exit 1
num=$(jq -er .num "$state") || exit 1
me=$(jq -er .me "$state") || exit 1
seen=$(jq -er .seen_head "$state") || exit 1
armed_at=$(jq -er .armed_at "$state") || exit 1
quiet_hours=$(jq -er .quiet_hours "$state") || exit 1

pr=$(gh pr view "$num" -R "$repo" --json state,isDraft,headRefOid) || exit 1
pr_state=$(jq -er .state <<<"$pr") || exit 1
if [ "$pr_state" != OPEN ]; then
  echo "pr:$pr_state"
  exit 0
fi

# A verdict review is one I posted with a decision or a body. Replying in an
# inline thread creates an empty-body COMMENTED review; that is not a verdict.
verdict=$(gh api --paginate "repos/$repo/pulls/$num/reviews" \
  | jq -rs --arg me "$me" '[.[][] | select(.user.login == $me)
           | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
                    or (.state == "COMMENTED" and (.body // "") != ""))]
           | last | .state // ""') || exit 1
if [ "$verdict" = APPROVED ]; then
  echo approved
  exit 0
fi

head=$(jq -er .headRefOid <<<"$pr") || exit 1
if [ "$(jq -r .isDraft <<<"$pr")" != true ] && [ "$head" != "$seen" ]; then
  echo "head:$seen..$head"
  exit 0
fi

committed_at=$(gh api "repos/$repo/commits/$head" -q .commit.committer.date) || exit 1
if jq -en --arg c "$committed_at" --arg a "$armed_at" --argjson h "$quiet_hours" \
  '([$c, $a] | map(fromdateiso8601) | max) + $h * 3600 < now' >/dev/null; then
  echo quiet
  exit 0
fi

exit 1
