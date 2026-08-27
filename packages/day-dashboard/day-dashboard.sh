#!/usr/bin/env bash
# day-dashboard — gather day/work context and render a private static dashboard.
#
# Pipeline:
#   1. run each source collector (graceful per-source degradation)
#   2. build a bounded context JSON
#   3. ask `pi -p` (cheap model, no tools, isolated) for a prioritized briefing
#   4. render injection-safe static HTML deterministically
#   5. publish atomically — the last good page is preserved on any failure
#
# It is safe to run by hand for testing:
#   DAY_DASHBOARD_STATE_DIR=/tmp/dd day-dashboard
#
# Environment (all optional):
#   DAY_DASHBOARD_STATE_DIR    base dir (default: $STATE_DIRECTORY or ./.dd-state)
#   DAY_DASHBOARD_SECRETS_DIR  credential files (default: $STATE_DIR/secrets)
#   DAY_DASHBOARD_MODEL        synthesis/aggregation model (default: openai-codex/gpt-5.6-sol)
#   DAY_DASHBOARD_MCP_MODEL    cheap model for the MCP collectors (default: openai-codex/gpt-5.6-luna)
#   DAY_DASHBOARD_MAX_ITEMS    per-source item cap (default: 8)
#   DAY_DASHBOARD_TZ           display timezone (default: system)
#   DAY_DASHBOARD_SOURCES      space list (default: "calendar email notes slack linear confluence")
#   DAY_DASHBOARD_MCP_CONFIG   MCP config for Slack/Linear (default: ~/.config/mcp/mcp.json)
#   DAY_DASHBOARD_SKIP_MODEL   if set, skip the synthesis model and render raw only
#   DAY_DASHBOARD_MCP_TTL_MIN  reuse cached Slack/Linear results this many minutes (default 120)
#   DAY_DASHBOARD_BRIEF_MAX_MIN  max age to reuse a cached briefing on unchanged context (default 360)
#   DAY_DASHBOARD_NO_CACHE     if set, ignore and do not write the cache
#   DAY_DASHBOARD_<SRC>_CMD    override a collector with a command printing {"items":[…]}
#   DAY_DASHBOARD_CONFLUENCE_BASE  see lib/collect.sh
#
# Slack/Linear collectors drive the Pi CLI against the MCP servers in
# DAY_DASHBOARD_MCP_CONFIG, and email/calendar use `gws`; all of those read the
# user's login keyring, so this must run inside the graphical session (as a
# systemd --user service), not as a bare system service.
set -uo pipefail

LIBDIR="${DAY_DASHBOARD_LIBDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../libexec/day-dashboard" 2>/dev/null && pwd)}"
# When run straight from the source tree (tests / dev), fall back to ./lib.
[ -f "$LIBDIR/collect.sh" ] || LIBDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/lib" && pwd)"

STATE_DIR="${DAY_DASHBOARD_STATE_DIR:-${STATE_DIRECTORY:-$PWD/.dd-state}}"
export SECRETS_DIR="${DAY_DASHBOARD_SECRETS_DIR:-$STATE_DIR/secrets}"
OUT_DIR="$STATE_DIR/www"
# Two-tier models: a cheap one just extracts each source (MCP_MODEL), a stronger
# one does the final aggregation/prioritization (MODEL) so related items — e.g.
# several notifications about the same issue — get merged into one.
MODEL="${DAY_DASHBOARD_MODEL:-openai-codex/gpt-5.6-sol}"
export DAY_DASHBOARD_MCP_MODEL="${DAY_DASHBOARD_MCP_MODEL:-openai-codex/gpt-5.6-luna}"
# Accept comma- or space-separated (systemd Environment= can't hold a space in
# a single value without quoting, so the unit passes a comma list).
SOURCES="${DAY_DASHBOARD_SOURCES:-calendar email notes slack linear github rootly confluence}"
SOURCES="${SOURCES//,/ }"
TZ_DISPLAY="${DAY_DASHBOARD_TZ:-$(date +%Z)}"
export MCP_CONFIG="${DAY_DASHBOARD_MCP_CONFIG:-$HOME/.config/mcp/mcp.json}"

mkdir -p "$OUT_DIR"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/day-dashboard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

log() { printf '[day-dashboard] %s\n' "$*" >&2; }

# shellcheck source=lib/collect.sh
. "$LIBDIR/collect.sh"

# ── cache ───────────────────────────────────────────────────────────────────
# One JSON file holds: TTL-cached results for the token-costly MCP collectors,
# the last synthesized briefing keyed by a context fingerprint (so an unchanged
# hour skips the model entirely), and an item ledger that remembers each
# meeting follow-up (first/last seen, ticket) so we know what is already tracked.
CACHE_FILE="$STATE_DIR/cache.json"
MCP_TTL_MIN="${DAY_DASHBOARD_MCP_TTL_MIN:-120}"
BRIEF_MAX_MIN="${DAY_DASHBOARD_BRIEF_MAX_MIN:-360}"
NOW_EPOCH="$(date +%s)"
TTL_SOURCES=" slack linear rootly "  # collectors that cost model tokens
cache='{}'
if [ -z "${DAY_DASHBOARD_NO_CACHE:-}" ] && [ -f "$CACHE_FILE" ]; then
  if c="$(cat "$CACHE_FILE" 2>/dev/null)" && jq -e . <<<"$c" >/dev/null 2>&1; then cache="$c"; fi
fi

# ── 1. collect ──────────────────────────────────────────────────────────────
# Sequential on purpose: the MCP collectors (Slack/Linear/Rootly) each drive the
# same model provider, which serializes concurrent sessions — running them in
# parallel just makes each slower and risks rate-limits, with no net speedup.
# Each cached (TTL) source is reused without a call; the 120-min cache means the
# full slow collect only happens roughly once every couple of hours.
records=()
for src in $SOURCES; do
  fn="collect_$src"
  if ! declare -F "$fn" >/dev/null; then
    log "unknown source: $src (skipping)"
    continue
  fi
  rec=""
  if [ -z "${DAY_DASHBOARD_NO_CACHE:-}" ] && [[ "$TTL_SOURCES" == *" $src "* ]]; then
    cAt="$(jq -r --arg s "$src" '.sources[$s].fetchedAtEpoch // 0' <<<"$cache")"
    cRec="$(jq -c --arg s "$src" '.sources[$s].record // empty' <<<"$cache")"
    if [ -n "$cRec" ] && [ "$(jq -r '.available // false' <<<"$cRec" 2>/dev/null)" = "true" ]; then
      ageMin=$(( (NOW_EPOCH - cAt) / 60 ))
      if [ "$ageMin" -lt "$MCP_TTL_MIN" ]; then
        log "$src: reused cache (${ageMin}m<${MCP_TTL_MIN}m TTL — saved a model call)"
        rec="$cRec"
      fi
    fi
  fi
  if [ -z "$rec" ]; then
    log "collecting $src"
    rec="$("$fn" 2>>"$WORK/collect.err")"
    # A collector must always emit valid JSON; if not, synthesize an unavailable
    # record so the pipeline never breaks on a bad source.
    if ! printf '%s' "$rec" | jq -e . >/dev/null 2>&1; then
      rec="$(jq -cn --arg s "$src" '{source:$s, available:false, reason:"collector crashed"}')"
    fi
    if [[ "$TTL_SOURCES" == *" $src "* ]] && [ "$(jq -r '.available // false' <<<"$rec" 2>/dev/null)" = "true" ]; then
      cache="$(jq -c --arg s "$src" --argjson r "$rec" --argjson t "$NOW_EPOCH" '.sources[$s]={fetchedAtEpoch:$t, record:$r}' <<<"$cache")"
    fi
  fi
  records+=("$rec")
done

# Combined context (source of truth for rendering).
printf '%s\n' "${records[@]}" | jq -cs '{sources: .}' >"$WORK/context.json"
avail_count="$(jq '[.sources[]|select(.available)]|length' "$WORK/context.json")"
log "sources available: $avail_count"

GENERATED_AT="$(date --iso-8601=seconds)"
DATE_LINE="$(date '+%A · %B %-d %Y')"
jq -cn --arg t "$GENERATED_AT" --arg tz "$TZ_DISPLAY" --arg m "$MODEL" --arg d "$DATE_LINE" \
  '{generatedAt:$t, now:$t, tz:$tz, model:$m, dateLine:$d}' >"$WORK/meta.json"

# ── 2/3. briefing via pi (cached when the context is unchanged) ─────────────
BRIEFING_ARG=()
briefing_source="none"
if [ -z "${DAY_DASHBOARD_SKIP_MODEL:-}" ] && [ "$avail_count" -gt 0 ]; then
  # Bound the context we send: only available sources, strings already capped by
  # collectors. This keeps token/cost budget tiny and predictable.
  ctx="$(jq -c '{sources:[.sources[]|select(.available)|{source, items}]}' "$WORK/context.json")"
  fp="$(printf '%s' "$ctx" | jq -cS . 2>/dev/null | sha256sum | cut -d' ' -f1)"
  lastFp="$(jq -r '.context.fingerprint // ""' <<<"$cache")"
  lastBrief="$(jq -c '.context.briefing // empty' <<<"$cache")"
  lastBriefEpoch="$(jq -r '.context.generatedAtEpoch // 0' <<<"$cache")"
  briefAge=$(( (NOW_EPOCH - lastBriefEpoch) / 60 ))
  if [ -z "${DAY_DASHBOARD_NO_CACHE:-}" ] && [ "$fp" = "$lastFp" ] && [ -n "$lastBrief" ] && [ "$briefAge" -lt "$BRIEF_MAX_MIN" ]; then
    log "context unchanged — reusing cached briefing (${briefAge}m old), skipped synthesis"
    printf '%s' "$lastBrief" >"$WORK/briefing.txt"
    BRIEFING_ARG=(--briefing "$WORK/briefing.txt")
    briefing_source="cache"
  else
    user_msg="Context:
$ctx

Current local time: $GENERATED_AT ($TZ_DISPLAY)

Produce the dashboard JSON now."
    log "requesting briefing from $MODEL"
    if pi -p \
        --no-session --no-tools --no-skills --no-extensions \
        --no-context-files --no-prompt-templates --no-themes --offline \
        --model "$MODEL" --thinking off \
        --system-prompt "$(cat "$LIBDIR/prompt.md")" \
        "$user_msg" >"$WORK/briefing.txt" 2>>"$WORK/pi.err"; then
      if [ -s "$WORK/briefing.txt" ]; then
        BRIEFING_ARG=(--briefing "$WORK/briefing.txt")
        briefing_source="model"
        log "briefing received ($(wc -c <"$WORK/briefing.txt") bytes)"
        # Cache the extracted object under this fingerprint for reuse next hour.
        if bobj="$(_extract_obj <"$WORK/briefing.txt" 2>/dev/null)" && [ -n "$bobj" ]; then
          cache="$(jq -c --arg fp "$fp" --argjson t "$NOW_EPOCH" --argjson b "$bobj" \
            '.context={fingerprint:$fp, generatedAtEpoch:$t, briefing:$b}' <<<"$cache")"
        fi
      else
        log "briefing empty; rendering raw only"
      fi
    else
      log "pi failed (exit $?); rendering raw only. stderr: $(tail -n1 "$WORK/pi.err" 2>/dev/null)"
    fi
  fi
else
  log "skipping model (skip flag or no sources)"
fi

# ── ledger: remember each meeting follow-up so we know what is already tracked
# and what is new. Keyed by "meeting|title"; carries first/last seen + ticket.
if [ ${#BRIEFING_ARG[@]} -gt 0 ]; then
  briefObj="$(_extract_obj <"$WORK/briefing.txt" 2>/dev/null || echo '{}')"
  seen="$(jq -c --argjson b "$briefObj" '[ (($b.actionGroups // $b.followupGroups) // [])[] | ((.kind//"other")+"|"+((.title//.meeting)//"")) as $g | (.items // [])[] | {key:($g+"|"+(.title//"")), status:(.status//"open"), ticket:(.ticket.id // null)} ]' <<<'{}' 2>/dev/null || echo '[]')"
  ledger="$(jq -c --argjson now "$NOW_EPOCH" --argjson seen "$seen" '
    (.ledger // {}) as $led
    | reduce $seen[] as $it ($led;
        .[$it.key] = ((.[$it.key] // {firstSeenEpoch:$now}) + {lastSeenEpoch:$now, status:$it.status, ticket:$it.ticket}))
    | [ to_entries[] | select((.value.lastSeenEpoch // 0) > ($now - 1209600)) ] | from_entries
  ' <<<"$cache" 2>/dev/null || jq -c '.ledger // {}' <<<"$cache")"
  cache="$(jq -c --argjson l "$ledger" '.ledger=$l' <<<"$cache")"
fi

# Persist the cache before rendering, so a later render failure still keeps the
# fetched data + briefing (and the last good page).
if [ -z "${DAY_DASHBOARD_NO_CACHE:-}" ]; then
  printf '%s' "$cache" >"$OUT_DIR/../.cache.json.new" 2>/dev/null \
    && mv -f "$OUT_DIR/../.cache.json.new" "$CACHE_FILE" 2>/dev/null || true
fi

# ── 4. render ───────────────────────────────────────────────────────────────
# Persist the render inputs so the dismiss handler can re-render instantly (from
# the last run) without re-collecting. dismissed.json is honored on every render.
DISMISSED_FILE="$STATE_DIR/dismissed.json"
install -m 0644 "$WORK/context.json" "$STATE_DIR/last-context.json" 2>/dev/null || true
install -m 0644 "$WORK/meta.json" "$STATE_DIR/last-meta.json" 2>/dev/null || true
if [ ${#BRIEFING_ARG[@]} -gt 0 ]; then
  _extract_obj <"$WORK/briefing.txt" 2>/dev/null >"$STATE_DIR/last-briefing.json" || echo 'null' >"$STATE_DIR/last-briefing.json"
else
  echo 'null' >"$STATE_DIR/last-briefing.json"
fi
[ -f "$DISMISSED_FILE" ] || echo '{}' >"$DISMISSED_FILE"

if ! node "$LIBDIR/render.mjs" \
    --context "$WORK/context.json" \
    "${BRIEFING_ARG[@]}" \
    --meta "$WORK/meta.json" \
    --asset-dir "$LIBDIR" \
    --dismissed "$DISMISSED_FILE" \
    --out "$WORK/index.html"; then
  log "render failed — PRESERVING last good page at $OUT_DIR/index.html"
  exit 1
fi

if [ ! -s "$WORK/index.html" ]; then
  log "render produced empty output — PRESERVING last good page"
  exit 1
fi

# ── 5. publish atomically ───────────────────────────────────────────────────
install -m 0644 "$WORK/index.html" "$OUT_DIR/.index.html.new"
mv -f "$OUT_DIR/.index.html.new" "$OUT_DIR/index.html"
# status.json is machine-readable run metadata (last success, per-source state).
trackedCount="$(jq -r '[.ledger // {} | to_entries[] | select(.value.status=="ticketed")] | length' <<<"$cache" 2>/dev/null || echo 0)"
jq -cn --slurpfile ctx "$WORK/context.json" --arg t "$GENERATED_AT" \
  --argjson brief "$( [ ${#BRIEFING_ARG[@]} -gt 0 ] && echo true || echo false )" \
  --arg bs "$briefing_source" --argjson tracked "${trackedCount:-0}" \
  '{lastSuccess:$t, briefing:$brief, briefingSource:$bs, trackedFollowups:$tracked,
    sources:[$ctx[0].sources[]|{source, available}]}' \
  >"$OUT_DIR/.status.json.new" 2>/dev/null \
  && mv -f "$OUT_DIR/.status.json.new" "$OUT_DIR/status.json"
log "published $OUT_DIR/index.html (briefing: $briefing_source, tracked follow-ups: ${trackedCount:-0})"
