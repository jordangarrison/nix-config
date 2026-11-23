#!/usr/bin/env bash
# Print one provider/model ID. A nonzero exit means use the agent pin.
set -eo pipefail

# Pi can migrate project files at startup, even with --no-approve.
scratch=$(mktemp -d /tmp/pi-review-models.XXXXXXXX)
trap 'rm -r -- "$scratch"' EXIT
catalog=$(cd "$scratch" && LC_ALL=C pi --no-approve --list-models sol)
awk '$1 ~ /^openai(-codex)?$/ && $2 ~ /^gpt-[0-9]+(\.[0-9]+)*-sol$/ { print $2, $1 }' <<< "$catalog" |
  LC_ALL=C sort -k1,1V |
  awk '
    { latest[$2] = $2 "/" $1 }
    END {
      if ("openai" in latest) print latest["openai"]
      else if ("openai-codex" in latest) print latest["openai-codex"]
      else exit 1
    }'
