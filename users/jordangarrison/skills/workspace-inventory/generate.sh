#!/usr/bin/env bash
# Generate .workspace.json — the repo inventory a workspace router doc
# (AGENTS.md -> ROUTER.md) points agents at. Run from anywhere:
#   generate.sh <workspace-dir>
# Writes <workspace-dir>/.workspace.json.
set -euo pipefail

ws="${1:?usage: generate.sh <workspace-dir>}"
ws="$(cd "$ws" && pwd)"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

detect_language() {
  local d="$1"
  if [ -f "$d/flake.nix" ] || [ -f "$d/default.nix" ]; then echo "nix"
  elif [ -f "$d/go.mod" ]; then echo "go"
  elif [ -f "$d/Cargo.toml" ]; then echo "rust"
  elif [ -f "$d/mix.exs" ]; then echo "elixir"
  elif [ -f "$d/Gemfile" ]; then echo "ruby"
  elif [ -f "$d/pyproject.toml" ] || [ -f "$d/setup.py" ] || [ -f "$d/requirements.txt" ]; then echo "python"
  elif [ -f "$d/package.json" ]; then echo "node"
  elif compgen -G "$d"/*.sln >/dev/null || compgen -G "$d"/*.csproj >/dev/null; then echo "dotnet"
  elif compgen -G "$d"/*.tf >/dev/null || [ -d "$d/terraform" ]; then echo "terraform"
  else echo "unknown"
  fi
}

# First meaningful prose line of the repo's own docs: skip headings, blank
# lines, and the boilerplate "This file provides guidance..." opener.
extract_description() {
  local d="$1" f
  for f in CLAUDE.md AGENTS.md README.md README; do
    [ -f "$d/$f" ] || continue
    awk '
      /^#/ { next }
      /^[[:space:]]*$/ { next }
      /^This file provides guidance/ { next }
      /^\[!\[/ { next }
      { gsub(/\*\*/, ""); print; exit }
    ' "$d/$f" | cut -c1-300
    return
  done
  echo ""
}

repos_json="[]"
for dir in "$ws"/*/; do
  d="${dir%/}"
  name="$(basename "$d")"
  [ -e "$d/.git" ] || continue

  branch="$(git -C "$d" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  [ -n "$branch" ] || branch="$(git -C "$d" symbolic-ref --short HEAD 2>/dev/null || echo "")"
  remote="$(git -C "$d" remote get-url origin 2>/dev/null || echo "")"
  language="$(detect_language "$d")"
  description="$(extract_description "$d")"
  has_agent_doc=false
  { [ -f "$d/CLAUDE.md" ] || [ -f "$d/AGENTS.md" ]; } && has_agent_doc=true

  repos_json="$(jq --arg name "$name" --arg desc "$description" \
    --arg lang "$language" --arg branch "$branch" --arg remote "$remote" \
    --argjson doc "$has_agent_doc" \
    '. + [{name: $name, description: $desc, language: $lang,
           defaultBranch: $branch, remote: $remote, hasAgentDoc: $doc}]' \
    <<<"$repos_json")"
done

jq -n --arg ws "$ws" --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson repos "$repos_json" \
  '{workspace: $ws, generatedAt: $date, repoCount: ($repos | length), repos: $repos}' \
  > "$ws/.workspace.json"

echo "Wrote $ws/.workspace.json ($(jq -r '.repoCount' "$ws/.workspace.json") repos)"
