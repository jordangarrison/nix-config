#!/usr/bin/env bash
# ngwaf.sh: incident client for the Fastly Next-Gen WAF (Signal Sciences) v0 API.
#
# Secret handling:
#   - The API token comes from 1Password (`op read`) or from a local file with
#     mode 600. The setup cache records WHERE the token is, never the token.
#   - The token reaches curl only through a stdin config (`--config -`) fed by
#     the printf builtin, so it never appears in argv, `ps`, shell history, a
#     file, or this script's output.
#   - get/corp-get refuse endpoints whose responses embed secrets, and curl
#     runs with --globoff so the path checked is the path requested.
#   - Writes are dry runs unless SIGSCI_ALLOW_WRITE equals the target site name.
#
# Run `ngwaf.sh help` for commands.
set -euo pipefail

# Own cache file: using-sigsci-waf's ~/.config/sigsci/config cannot read the
# file token source, so sharing it would break that skill.
CONFIG_FILE="${NGWAF_CONFIG:-$HOME/.config/ngwaf-incident/config}"
LEGACY_CONFIG="$HOME/.config/sigsci/config"
API_HOST="https://dashboard.signalsciences.net"
# Test seam: an API base override may only be a bare loopback authority, so no
# environment change can send the token to another host.
if [ -n "${SIGSCI_API_BASE:-}" ]; then
  if [[ "$SIGSCI_API_BASE" =~ ^http://(127\.0\.0\.1|localhost):[0-9]{1,5}$ ]]; then API_HOST="$SIGSCI_API_BASE"
  else printf 'ngwaf: SIGSCI_API_BASE must be exactly http://127.0.0.1:<port> or http://localhost:<port>\n' >&2; exit 1; fi
fi
API_BASE="$API_HOST/api/v0"

# Exit codes the skill branches on.
EXIT_SETUP=3   # setup cache missing or incomplete: run setup
EXIT_AUTH=4    # token unreadable or rejected (HTTP 401/403): run setup
EXIT_API=5     # API or network error that is not an auth failure: retry, report
EXIT_PARTIAL=2 # feed stopped early: output is truncated
HTTP_AUTH=41   # api(): the API rejected the credentials

die() { printf 'ngwaf: %s\n' "$*" >&2; exit 1; }
die_code() { local c=$1; shift; printf 'ngwaf: %s\n' "$*" >&2; exit "$c"; }
note() { printf 'ngwaf: %s\n' "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"; }
need curl; need jq

# Single-quote a value so it is safe to source back.
shquote() { local s=${1//\'/\'\\\'\'}; printf "'%s'" "$s"; }

now() { date -u +%s; }
iso() { jq -nr --argjson t "$1" '$t | todate'; }

# Octal permission bits of a file, GNU or BSD stat.
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# A token file must be readable by its owner only.
assert_private() {
  [ -f "$1" ] || die_code $EXIT_AUTH "token file '$1' does not exist"
  local m; m=$(file_mode "$1")
  case "$m" in
    600|400|0600|0400) ;;
    *) die_code $EXIT_AUTH "token file '$1' has mode $m; run: chmod 600 '$1'" ;;
  esac
}

# Value of NAME=VALUE (optionally `export NAME=...`, optionally quoted) in an env-style file.
env_value() {
  sed -n -e "s/^export $2=//p" -e "s/^$2=//p" "$1" | tail -n 1 | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/"
}

# Parse a time: unix seconds, -30m/-2h/-1d relative to now, or ISO-8601 UTC.
to_epoch() {
  local t="$1" n; n=$(now)
  case "$t" in
    ''|now) printf '%s' "$n" ;;
    -*[0-9]min|-*[0-9]m) printf '%s' $(( n - ${t//[^0-9]/} * 60 )) ;;
    -*[0-9]h) printf '%s' $(( n - ${t//[^0-9]/} * 3600 )) ;;
    -*[0-9]d) printf '%s' $(( n - ${t//[^0-9]/} * 86400 )) ;;
    *[!0-9]*) jq -nr --arg t "$t" '$t | sub("\\.[0-9]+"; "") | fromdateiso8601' 2>/dev/null \
                || die "cannot parse time '$t' (use unix seconds, -30m, -2h, -1d, or 2026-01-31T00:40:00Z)" ;;
    *) printf '%s' "$t" ;;
  esac
}

# --- setup cache --------------------------------------------------------------

# Env values override the cache, so `SIGSCI_SITE=other ngwaf.sh rules` targets
# `other` even though the cache names a different site.
load_config() {
  local _corp="${SIGSCI_CORP:-}" _site="${SIGSCI_SITE:-}" _user="${SIGSCI_API_USER:-}"
  if [ ! -f "$CONFIG_FILE" ]; then
    [ -f "$LEGACY_CONFIG" ] && note "using-sigsci-waf's cache $LEGACY_CONFIG exists; its SIGSCI_OP_REF can be passed to: setup --op"
    die_code $EXIT_SETUP "no setup cache at $CONFIG_FILE; run setup"
  fi
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
  [ -n "$_corp" ] && SIGSCI_CORP="$_corp"
  [ -n "$_site" ] && SIGSCI_SITE="$_site"
  [ -n "$_user" ] && SIGSCI_API_USER="$_user"
  # Caches written by the older using-sigsci-waf helper carry only SIGSCI_OP_REF.
  if [ -z "${SIGSCI_TOKEN_SOURCE:-}" ] && [ -n "${SIGSCI_OP_REF:-}" ]; then SIGSCI_TOKEN_SOURCE=op; fi
  local missing=""
  for v in SIGSCI_TOKEN_SOURCE SIGSCI_CORP SIGSCI_SITE SIGSCI_API_USER; do
    eval "[ -n \"\${$v:-}\" ]" || missing="$missing $v"
  done
  [ -z "$missing" ] || die_code $EXIT_SETUP "setup cache $CONFIG_FILE lacks:$missing; run setup"
}

get_token() {
  case "$SIGSCI_TOKEN_SOURCE" in
    op)
      command -v op >/dev/null 2>&1 || die_code $EXIT_AUTH "the 1Password CLI 'op' is not installed"
      local args=(read)
      [ -n "${SIGSCI_OP_ACCOUNT:-}" ] && args+=(--account "$SIGSCI_OP_ACCOUNT")
      op "${args[@]}" "$SIGSCI_OP_REF" 2>/dev/null \
        || die_code $EXIT_AUTH "could not read the token from 1Password ($SIGSCI_OP_REF); is op signed in?"
      ;;
    file)
      assert_private "$SIGSCI_TOKEN_FILE"
      local tok
      if [ -n "${SIGSCI_TOKEN_VAR:-}" ]; then tok=$(env_value "$SIGSCI_TOKEN_FILE" "$SIGSCI_TOKEN_VAR")
      else tok=$(sed -n '/[^[:space:]]/{p;q;}' "$SIGSCI_TOKEN_FILE" | tr -d '[:space:]'); fi
      [ -n "$tok" ] || die_code $EXIT_AUTH "no token found in $SIGSCI_TOKEN_FILE${SIGSCI_TOKEN_VAR:+ (variable $SIGSCI_TOKEN_VAR)}"
      printf '%s' "$tok"
      ;;
    *) die_code $EXIT_SETUP "unknown token source '$SIGSCI_TOKEN_SOURCE' in $CONFIG_FILE; run setup" ;;
  esac
}

write_config() { # writes the cache from the current SIGSCI_* values
  mkdir -p "$(dirname "$CONFIG_FILE")"
  local tmp; tmp=$(umask 077; mktemp "$CONFIG_FILE.XXXXXX")
  {
    echo "# Fastly NG WAF setup cache (ngwaf-incident skill). NOT SECRET: no token here."
    echo "SIGSCI_TOKEN_SOURCE=$(shquote "$SIGSCI_TOKEN_SOURCE")"
    [ -n "${SIGSCI_OP_REF:-}" ]     && echo "SIGSCI_OP_REF=$(shquote "$SIGSCI_OP_REF")"
    [ -n "${SIGSCI_OP_ACCOUNT:-}" ] && echo "SIGSCI_OP_ACCOUNT=$(shquote "$SIGSCI_OP_ACCOUNT")"
    [ -n "${SIGSCI_TOKEN_FILE:-}" ] && echo "SIGSCI_TOKEN_FILE=$(shquote "$SIGSCI_TOKEN_FILE")"
    [ -n "${SIGSCI_TOKEN_VAR:-}" ]  && echo "SIGSCI_TOKEN_VAR=$(shquote "$SIGSCI_TOKEN_VAR")"
    echo "SIGSCI_CORP=$(shquote "$SIGSCI_CORP")"
    echo "SIGSCI_SITE=$(shquote "$SIGSCI_SITE")"
    echo "SIGSCI_API_USER=$(shquote "$SIGSCI_API_USER")"
    echo "SIGSCI_VERIFIED_AT=$(shquote "${SIGSCI_VERIFIED_AT:-}")"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}

# Record a passing auth test without rewriting anything else in the cache
# (env overrides such as SIGSCI_SITE=... must not leak into it).
stamp_verified() {
  local tmp; tmp=$(umask 077; mktemp "$CONFIG_FILE.XXXXXX")
  { grep -v '^SIGSCI_VERIFIED_AT=' "$CONFIG_FILE" || true; echo "SIGSCI_VERIFIED_AT=$(shquote "$SIGSCI_VERIFIED_AT")"; } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$CONFIG_FILE"
}

# --- HTTP ---------------------------------------------------------------------

# api METHOD PATH_OR_URI [curl args...]
# PATH is relative to /api/v0; a URI starting with /api/ (a feed next.uri) is
# relative to the host. Prints the body of the last attempt. Returns 0 on 2xx,
# HTTP_AUTH on 401/403, EXIT_API on any other HTTP or network failure, or
# get_token's code. GET and PUT retry 429, 5xx, and network errors; POST never
# retries, since a retried create can land twice.
api() {
  local method="$1" target="$2"; shift 2
  local url
  case "$target" in /api/*) url="$API_HOST$target" ;; *) url="$API_BASE$target" ;; esac
  local token; token=$(get_token) || return $?
  local out; out=$(umask 077; mktemp)
  local tries=3 n=0 code rc
  [ "$method" = POST ] && tries=1
  while :; do
    n=$((n + 1)); rc=0
    # -o rewrites the file on every attempt, so a failed attempt's body never
    # precedes the good one.
    code=$(printf 'header = "x-api-user: %s"\nheader = "x-api-token: %s"\nheader = "Content-Type: application/json"\n' \
        "$SIGSCI_API_USER" "$token" \
      | curl -sS --globoff --max-time "${SIGSCI_MAX_TIME:-180}" -X "$method" "$@" \
          -o "$out" -w '%{http_code}' --config - "$url") || rc=$?
    if [ $rc -eq 0 ]; then
      case "$code" in 2??) cat "$out"; rm -f "$out"; return 0 ;; 429|5??) ;; *) break ;; esac
    fi
    [ $n -lt $tries ] || break
    sleep $((n * 2))
  done
  cat "$out"; rm -f "$out"
  if [ $rc -ne 0 ]; then note "network error (curl exit $rc) on $method ${target%%\?*}"; return $EXIT_API; fi
  note "HTTP $code from $method ${target%%\?*}"
  case "$code" in 401|403) return $HTTP_AUTH ;; *) return $EXIT_API ;; esac
}

site_path() { printf '/corps/%s/sites/%s%s' "$SIGSCI_CORP" "$SIGSCI_SITE" "$1"; }

# Only plain paths: no `.`/`..` segments (curl squashes them, which could
# escape a prefix), and no fragment, glob, or percent-encoding, which would make
# the path requested differ from the path checked.
assert_safe_path() {
  local p="${1%%\?*}"
  case "$p" in /*) ;; *) die "path must start with / (got '$1')" ;; esac
  case "$p" in *[!A-Za-z0-9/._-]*) die "path may contain only letters, digits, and / . _ - (got '$1')" ;; esac
  case "$1" in *'#'*) die "path must not contain '#' (got '$1')" ;; esac
  case "$p/" in */../*|*/./*) die "path must not contain '.' or '..' segments (got '$1')" ;; esac
}

# Refuse GET endpoints whose responses embed secrets: agent keys, integration
# webhook URLs, and monitor share links. View those in the control panel.
assert_not_secret() {
  case "${1%%\?*}" in
    */agentKeys|*/agentKeys/*|*/keys|*/keys/*|*/integrations|*/integrations/*|*/monitors|*/monitors/*)
      die "refusing '$1': this endpoint returns secrets; use the control panel" ;;
  esac
}

# Writes run only when SIGSCI_ALLOW_WRITE names the target site exactly.
write_allowed() {
  [ "${SIGSCI_ALLOW_WRITE:-}" = "$SIGSCI_SITE" ] && return 0
  [ -z "${SIGSCI_ALLOW_WRITE:-}" ] || note "SIGSCI_ALLOW_WRITE=$SIGSCI_ALLOW_WRITE does not match the target site $SIGSCI_SITE"
  return 1
}

TMPD=""
tmpdir() { [ -n "$TMPD" ] || { TMPD=$(umask 077; mktemp -d); trap 'rm -rf "$TMPD"' EXIT; }; }

# --- commands -----------------------------------------------------------------

cmd_setup() {
  local src="" ref="" acct="" file="" var="" var_set=0 corp="" site="" user=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --op) src="op"; ref="$2"; shift 2 ;;
      --op-account) acct="$2"; shift 2 ;;
      --file) src="file"; file="$2"; shift 2 ;;
      --var) var="$2"; var_set=1; shift 2 ;;
      --corp) corp="$2"; shift 2 ;;
      --site) site="$2"; shift 2 ;;
      --user) user="$2"; shift 2 ;;
      *) die "setup: unknown flag '$1' (see: ngwaf.sh help)" ;;
    esac
  done
  case "$src" in
    op)
      case "$ref" in op://*/*/*) ;; *) die "setup: --op needs a full secret reference, op://<vault>/<item>/<field>" ;; esac ;;
    file)
      case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
      assert_private "$file"
      # An env-style file names the token variable; a one-line file is the raw token.
      if [ $var_set = 0 ] && grep -q '^\(export \)\{0,1\}SIGSCI_TOKEN=' "$file"; then var=SIGSCI_TOKEN; fi
      # Non-secret values may come from the same env file.
      [ -n "$corp" ] || corp=$(env_value "$file" SIGSCI_CORP)
      [ -n "$site" ] || site=$(env_value "$file" SIGSCI_SITE)
      [ -n "$user" ] || user=$(env_value "$file" SIGSCI_API_USER)
      [ -n "$user" ] || user=$(env_value "$file" SIGSCI_EMAIL)
      ;;
    *) die "setup: choose a token source: --op <op://ref> or --file <path>" ;;
  esac
  [ -n "$corp" ] && [ -n "$site" ] && [ -n "$user" ] || die "setup: --corp, --site and --user are all required"
  if [ -f "$CONFIG_FILE" ]; then cp -p "$CONFIG_FILE" "$CONFIG_FILE.prev"; note "kept the previous cache at $CONFIG_FILE.prev"; fi
  SIGSCI_TOKEN_SOURCE=$src SIGSCI_OP_REF=$ref SIGSCI_OP_ACCOUNT=$acct SIGSCI_TOKEN_FILE=$file SIGSCI_TOKEN_VAR=$var
  SIGSCI_CORP=$corp SIGSCI_SITE=$site SIGSCI_API_USER=$user SIGSCI_VERIFIED_AT=""
  write_config
  note "wrote $CONFIG_FILE (mode 600, no token); testing auth"
  cmd_auth_test
}

cmd_auth_test() {
  load_config
  tmpdir
  local body rc=0
  body=$(api GET "$(site_path "")" 2>"$TMPD/err") || rc=$?
  local msg; msg=$(printf '%s' "$body" | jq -r '.message? // empty' 2>/dev/null | head -c 300 || true)
  case $rc in
    0) ;;
    "$HTTP_AUTH") die_code $EXIT_AUTH "the API rejected $SIGSCI_API_USER on $SIGSCI_CORP/$SIGSCI_SITE: ${msg:-HTTP 401/403}" ;;
    "$EXIT_SETUP"|"$EXIT_AUTH") cat "$TMPD/err" >&2; exit $rc ;;   # get_token's reason
    *) cat "$TMPD/err" >&2; die_code $EXIT_API "API or network error, not an auth failure${msg:+: $msg}; retry" ;;
  esac
  SIGSCI_VERIFIED_AT=$(iso "$(now)")
  stamp_verified
  printf '%s' "$body" | jq -r --arg u "$SIGSCI_API_USER" --arg c "$SIGSCI_CORP" --arg src "$SIGSCI_TOKEN_SOURCE" --arg at "$SIGSCI_VERIFIED_AT" '
    "ok: \($u) on \($c)/\(.name) (\(.displayName)); agentLevel=\(.agentLevel) blockHTTPCode=\(.blockHTTPCode); token from \($src); verified \($at)",
    (if .agentLevel != "block" then "warning: agentLevel is \(.agentLevel), so block rules on this site do not block" else empty end)'
}

# Normalised rule list: site rules plus corp rules that apply to this site.
# fetch_all PATH OUT: every page of a list endpoint into OUT as
# {"data": [...], "totalCount": N}. Returns api's code on failure.
fetch_all() {
  local path="$1" out="$2" page=1 got=0 total=0 n rc
  : > "$out.items"
  while :; do
    rc=0; api GET "$path?limit=100&page=$page" > "$out.page" 2>"$out.err" || rc=$?
    [ $rc -eq 0 ] || { cat "$out.err" >&2; return $rc; }
    jq -e 'type == "object" and (.data | type == "array")' "$out.page" >/dev/null || { note "unexpected response from $path"; return $EXIT_API; }
    jq -c '.data[]' "$out.page" >> "$out.items"
    n=$(jq '.data | length' "$out.page"); total=$(jq '.totalCount // 0' "$out.page"); got=$((got + n))
    if [ "$n" -eq 0 ] || [ "$got" -ge "$total" ]; then break; fi
    page=$((page + 1))
  done
  jq -s --argjson t "$total" '{data: ., totalCount: $t}' "$out.items" > "$out"
}

# Normalised view: site rules, corp rules that apply to this site, and site
# alerts, plus what was and was not read. A read that fails is reported in
# .coverage, never treated as an empty list.
rules_json() {
  tmpdir
  fetch_all "$(site_path /rules)" "$TMPD/site-rules.json"
  local corp_err="" alerts_err="" rc
  rc=0; fetch_all "/corps/$SIGSCI_CORP/rules" "$TMPD/corp-rules.json" 2>"$TMPD/corp.err" || rc=$?
  if [ $rc -ne 0 ]; then corp_err=$(tr '\n' ' ' < "$TMPD/corp.err" | head -c 200); echo '{"data":[],"totalCount":0}' > "$TMPD/corp-rules.json"; fi
  rc=0; api GET "$(site_path /alerts)" > "$TMPD/alerts.json" 2>"$TMPD/alerts.err" || rc=$?
  if [ $rc -ne 0 ] || ! jq -e '.data | type == "array"' "$TMPD/alerts.json" >/dev/null 2>&1; then
    alerts_err=$(tr '\n' ' ' < "$TMPD/alerts.err" | head -c 200); echo '{"data":[]}' > "$TMPD/alerts.json"
  fi
  jq -n --slurpfile s "$TMPD/site-rules.json" --slurpfile c "$TMPD/corp-rules.json" --slurpfile a "$TMPD/alerts.json" \
        --arg site "$SIGSCI_SITE" --arg corp_err "$corp_err" --arg alerts_err "$alerts_err" '
    def signals_matched: [.. | objects | select(.field? == "signalType" or .field? == "signal") | .value? // empty] | unique;
    {
      coverage: {
        site_rules: {read: ($s[0].data | length), total: $s[0].totalCount},
        corp_rules: (if $corp_err == "" then {read: ($c[0].data | length), total: $c[0].totalCount} else {error: $corp_err} end),
        alerts: (if $alerts_err == "" then {read: ($a[0].data | length)} else {error: $alerts_err} end)
      },
      rules: (([$s[0].data[] | . + {scope: "site"}]
               + [$c[0].data[] | select(.corpScope == "global" or ((.siteNames // []) | index($site))) | . + {scope: "corp"}])
        | map({
            id, scope, enabled, type,
            actions: [.actions[]?.type],
            blocks: ([.actions[]?.type] | any(. == "block" or . == "blockSignal")),
            adds: ([.actions[]?.signal, .signal] | map(select(. != null and . != "")) | unique),
            matches: signals_matched,
            fields: ([.. | objects | .field? // empty] | unique - ["name", "signalType", "signal"]),
            requestLogging, expiration,
            reason: (.reason // "")
          })),
      # flagged and blockImmediate alerts block traffic once the signal crosses the threshold.
      alerts: [$a[0].data[] | {id, tagName, action, enabled, threshold, interval,
                               blocks: (.action | test("flagged|block"; "i"))}]
    }
    | .complete = ((.coverage.site_rules.read >= .coverage.site_rules.total)
                   and (.coverage.corp_rules.error == null) and (.coverage.alerts.error == null))'
}

cmd_rules() {
  load_config
  tmpdir
  rules_json > "$TMPD/rules.json"
  if [ "${1:-}" = "--json" ]; then cat "$TMPD/rules.json"; return; fi
  jq -r '
    def kind: if .blocks then "BLOCK" elif (.actions | index("allow")) then "ALLOW"
              elif .type == "rateLimit" then "RATELIMIT-LOG" else "OBSERVE" end;
    def cov(c): if c.error then "NOT READ (\(c.error))" else "\(c.read)" + (if c.total then "/\(c.total)" else "" end) end;
    .rules as $all
    | ($all | map(select(.enabled and .blocks))) as $blockers
    | (.alerts | map(select(.enabled and .blocks))) as $balerts
    | .complete as $complete
    | "== coverage: site rules \(cov(.coverage.site_rules)), corp rules \(cov(.coverage.corp_rules)), alerts \(cov(.coverage.alerts))",
      (if $complete then empty else "   INCOMPLETE: a blocker may be missing from this view; check the control panel before concluding a signal is observe-only" end),
    "",
    "== rules (\($all | length)); fields = request fields the conditions test",
    ($all[] | "\(.id) \(if .enabled then "on " else "OFF" end) \(.scope) \(kind)" +
           (if (.fields | length) > 0 then "  fields=\(.fields | join(","))" else "" end) +
           (if (.matches | length) > 0 then "  matches-signals=\(.matches | join(","))" else "" end) +
           (if (.adds | length) > 0 then "  adds=\(.adds | join(","))" else "" end) +
           "\n    \(.reason | gsub("\\s+"; " ") | .[0:140])"),
    "",
    "== each signal a rule adds: who adds it, and what can block on it",
    ( [$all[] | .adds[]] | unique | .[] as $sig
      | ($all | map(select(.adds | index($sig)) | "\(.id[0:8])(\(kind)\(if .enabled then "" else ",OFF" end))") | join(" ")) as $by
      | ($blockers | map(select(.matches | index($sig)) | .id[0:8])) as $bl
      | ($balerts | map(select(.tagName == $sig) | "\(.action)>\(.threshold)/\(.interval)m")) as $al
      | "\($sig)\n    added by \($by)" +
        "\n    matched by block rules: \(if ($bl | length) > 0 then $bl | join(" ") else "none" end)" +
        "\n    blocking alerts: \(if ($al | length) > 0 then $al | join(" ") else "none" end)" +
        (if ($bl | length) == 0 and ($al | length) == 0 then
           (if $complete then "\n    => observe only" else "\n    => unknown (coverage incomplete)" end)
         else "" end)),
    "",
    "== signals that enabled block rules match on",
    ( [$blockers[] | .matches[]] | unique | .[] as $sig
      | "\($sig): \([$blockers[] | select(.matches | index($sig)) | .id[0:8]] | join(" "))" ),
    "",
    "== enabled blocking alerts",
    ($balerts[] | "\(.tagName): \(.action) threshold=\(.threshold) interval=\(.interval)m")
  ' "$TMPD/rules.json"
  note "ids shortened to 8 chars in the summaries; a block rule that matches a signal may also test other fields before it blocks"
}

# Validate and align a feed window; sets FEED_FROM and FEED_UNTIL.
feed_window() {
  local n limit
  FEED_FROM=$(to_epoch "$1"); FEED_UNTIL=$(to_epoch "$2"); n=$(now)
  FEED_FROM=$(( FEED_FROM / 60 * 60 )); FEED_UNTIL=$(( FEED_UNTIL / 60 * 60 ))
  limit=$(( (n - 300) / 60 * 60 ))
  if [ "$FEED_UNTIL" -gt "$limit" ]; then
    note "until moved back to $(iso $limit): the feed serves only windows ending 5+ minutes ago"; FEED_UNTIL=$limit
  fi
  [ "$FEED_FROM" -lt "$FEED_UNTIL" ] || die "empty window ($(iso $FEED_FROM) to $(iso $FEED_UNTIL))"
  [ $(( FEED_UNTIL - FEED_FROM )) -le 86400 ] || die "the feed window is at most 24h; split it"
  [ "$FEED_FROM" -ge $(( n - 168 * 3600 )) ] || die "the feed keeps 168h (7 days); from $(iso $FEED_FROM) is too old"
}

# Every flagged request in FEED_FROM..FEED_UNTIL as NDJSON, paging via next.uri.
# Returns EXIT_PARTIAL, after printing what it has, if a page fails.
feed_pages() {
  tmpdir
  local uri page=0 total=0 cnt
  uri="$(site_path /feed/requests)?from=$FEED_FROM&until=$FEED_UNTIL"
  note "feed $(iso $FEED_FROM) to $(iso $FEED_UNTIL)"
  while [ -n "$uri" ]; do
    if ! api GET "$uri" > "$TMPD/page.json" 2>"$TMPD/err" || ! jq -e 'type == "object" and (.data | type == "array")' "$TMPD/page.json" >/dev/null 2>&1; then
      note "page $((page + 1)) failed after $total records: $(cat "$TMPD/page.json" "$TMPD/err" 2>/dev/null | head -c 300 | tr '\n' ' ')"
      note "TRUNCATED: output covers only the first $page pages"
      return $EXIT_PARTIAL
    fi
    jq -c '.data[]' "$TMPD/page.json"
    cnt=$(jq '.data | length' "$TMPD/page.json"); total=$((total + cnt)); page=$((page + 1))
    if [ $((page % 10)) -eq 0 ]; then note "page $page, $total records"; fi
    uri=$(jq -r '.next.uri // ""' "$TMPD/page.json")
  done
  note "complete: $page pages, $total records"
}

cmd_feed() {
  load_config
  [ $# -ge 2 ] || die "feed needs FROM UNTIL (unix seconds, -30m, -2h, or ISO-8601 UTC)"
  feed_window "$1" "$2"
  feed_pages
}

cmd_timeseries() {
  load_config
  local json=0 pos=() a
  for a in "$@"; do if [ "$a" = "--json" ]; then json=1; else pos+=("$a"); fi; done
  set -- ${pos[@]+"${pos[@]}"}
  local tags="${1:-}" from until rollup="${4:-60}" tl t
  [ -n "$tags" ] || die "timeseries needs TAG[,TAG...] (a signal, e.g. BLOCKED or site.bad-bot-traffic)"
  from=$(to_epoch "${2:--1h}"); until=$(to_epoch "${3:-now}")
  local args=(-G --data-urlencode "from=$from" --data-urlencode "until=$until" --data-urlencode "rollup=$rollup")
  IFS=, read -r -a tl <<< "$tags"
  for t in "${tl[@]}"; do args+=(--data-urlencode "tag=$t"); done
  local body; body=$(api GET "$(site_path /timeseries/requests)" "${args[@]}")
  if [ $json = 1 ]; then printf '%s\n' "$body"; return; fi
  printf '%s' "$body" | jq -r '
    .data as $d
    | (["time_utc"] + ($d | map("\(.type)(total=\(.summaryCount))"))) | @tsv,
      ( range(0; ($d[0].data | length)) as $i
        | [($d[0].from + $i * $d[0].inc | todate)] + ($d | map(.data[$i])) | @tsv )'
}

cmd_search() {
  load_config
  [ -n "${1:-}" ] || die "search needs a QUERY in NGWAF search syntax, e.g. \"from:-30min httpcode:406\""
  api GET "$(site_path /requests)" -G --data-urlencode "q=$1" --data-urlencode "limit=${2:-100}" \
    || die "search failed (it has returned 500 during incidents); use: ngwaf.sh feed FROM UNTIL"
}

# verify-rule ID FROM UNTIL [--host HOST] [--ua REGEX]
cmd_verify_rule() {
  load_config
  [ $# -ge 3 ] || die "verify-rule needs RULE_ID FROM UNTIL [--host HOST] [--ua REGEX] [--path REGEX]"
  local id="$1" from="$2" until="$3" host="" ua="" path=""; shift 3
  case "$id" in *[!a-zA-Z0-9]*) die "rule id must be alphanumeric (got '$id')" ;; esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --host) host="$2"; shift 2 ;; --ua) ua="$2"; shift 2 ;; --path) path="$2"; shift 2 ;;
      *) die "verify-rule: unknown flag '$1'" ;;
    esac
  done
  local rule; rule=$(api GET "$(site_path "/rules/$id")") || die "rule $id not found on $SIGSCI_CORP/$SIGSCI_SITE"
  printf '%s' "$rule" | jq -r '"rule \(.id) enabled=\(.enabled) actions=\([.actions[].type] | join(",")) requestLogging=\(.requestLogging)\n  \(.reason | gsub("\\s+"; " ") | .[0:200])"'
  feed_window "$from" "$until"
  # Hits can only exist after the rule's last change; earlier traffic would
  # show as misses.
  local changed; changed=$(printf '%s' "$rule" | jq -r '(.updated // .created // "") | sub("\\.[0-9]+"; "") | if . == "" then 0 else fromdateiso8601 end')
  if [ "$FEED_FROM" -lt "$changed" ]; then
    note "WARNING: the window starts before the rule's last change at $(iso "$changed"); for a post-change check use FROM >= $(iso $(( (changed + 59) / 60 * 60 )))"
  fi
  tmpdir
  local rc=0
  feed_pages > "$TMPD/feed.ndjson" || rc=$?
  jq -nr --arg id "$id" --arg host "$host" --arg ua "$ua" --arg path "$path" '
    def bump(k): .[k] = ((.[k] // 0) + 1);
    def top(n): to_entries | sort_by(-.value) | .[0:n] | map("    \(.value)\t\(.key)") | .[];
    reduce inputs as $r ({n: 0, hit: {n: 0, code: {}, ua: {}, path: {}, host: {}}, other: {n: 0, by: {}}, fp: {n: 0, code: {}, path: {}}};
      .n += 1
      | ([$r.tags[]? | select(.type == "BLOCKED")][0].detector // null) as $blk
      | (($r.tags // []) | any(.detector == $id)) as $mine
      | if $mine then
          .hit.n += 1 | .hit.code |= bump("\($r.responseCode)") | .hit.ua |= bump(($r.userAgent // "")[0:160])
          | .hit.path |= bump($r.path // "") | .hit.host |= bump($r.serverName // "")
        elif $blk != null then .other.n += 1 | .other.by |= bump($blk)
        else . end
      | if ($host != "" or $ua != "" or $path != "") and ($mine | not)
           and ($host == "" or $r.serverName == $host) and ($ua == "" or (($r.userAgent // "") | test($ua)))
           and ($path == "" or (($r.path // "") | test($path))) then
          .fp.n += 1 | .fp.code |= bump("\($r.responseCode)" + (if $blk then " blocked by \($blk)" else "" end)) | .fp.path |= bump($r.path // "")
        else . end)
    | "flagged requests in window: \(.n)",
      "attributed to this rule (a tag names it as detector): \(.hit.n)",
      "  by response code:", (.hit.code | top(10)),
      "  top user agents:", (.hit.ua | top(5)),
      "  top paths:", (.hit.path | top(10)),
      "  hosts:", (.hit.host | top(5)),
      "blocked by OTHER rules (same block code, different detector): \(.other.n)",
      (.other.by | top(5)),
      (if $host != "" or $ua != "" or $path != "" then
         "candidates (host=\(if $host == "" then "*" else $host end) ua=~\(if $ua == "" then "*" else $ua end) path=~\(if $path == "" then "*" else $path end)) NOT attributed to this rule: \(.fp.n)",
         "  these match only the filters given, not every rule condition (headers are not checked): inspect them before calling any a miss",
         "  by response code:", (.fp.code | top(10)),
         "  top paths:", (.fp.path | top(10))
       else empty end)' < "$TMPD/feed.ndjson"
  note "the feed holds flagged requests only, and requestLogging=sampled logs a sample: counts are lower bounds"
  note "a status code alone does not prove this rule fired: other block rules return the same code; attribution above uses the tag detector"
  return $rc
}

# Strip read-only fields and nulls so a fetched rule can be sent back with PUT.
writable_rule() {
  jq 'del(.id, .siteNames, .createdBy, .created, .updated, .customer_id)
      | walk(if type == "object" then with_entries(select(.value != null)) else . end)'
}

cmd_create() {
  load_config
  local src="${1:-}"; [ -n "$src" ] || die "create needs a rule JSON file (or - for stdin)"
  tmpdir
  if [ "$src" = "-" ]; then cat > "$TMPD/body.json"; else cp "$src" "$TMPD/body.json"; fi
  jq -e 'type == "object" and (.id | not) and (.type | type == "string") and (.groupOperator | type == "string")
         and (.conditions | length > 0) and (.actions | length > 0) and (.reason | type == "string" and length > 0)
         and has("enabled") and has("expiration")' "$TMPD/body.json" >/dev/null \
    || die "rule body needs type, enabled, groupOperator, conditions, actions, reason, expiration, and no id (see rule-schema.md)"
  printf 'target: %s/%s  POST %s\n' "$SIGSCI_CORP" "$SIGSCI_SITE" "$(site_path /rules)"
  jq . "$TMPD/body.json"
  if ! write_allowed; then
    printf 'DRY RUN: nothing sent. To apply, re-run with SIGSCI_ALLOW_WRITE=%s\n' "$SIGSCI_SITE"; return 0
  fi
  # Not retried: if the API committed the rule before failing, a retry would make a second one.
  local out rc=0; out=$(api POST "$(site_path /rules)" --data-binary @"$TMPD/body.json") || rc=$?
  if [ $rc -ne 0 ]; then
    note "create failed (${out:0:300}); the rule may still have been created"
    die "before retrying, run 'ngwaf.sh rules' and look for this rule's reason"
  fi
  printf '%s' "$out" | jq -r '"created \(.id) enabled=\(.enabled) on \(.siteNames | join(","))\nrollback: ngwaf.sh disable \(.id)"'
}

cmd_disable() {
  load_config
  local id="${1:-}"; [ -n "$id" ] || die "disable needs a RULE_ID"
  case "$id" in *[!a-zA-Z0-9]*) die "rule id must be alphanumeric (got '$id')" ;; esac
  tmpdir
  api GET "$(site_path "/rules/$id")" > "$TMPD/rule.json" || die "rule $id not found on $SIGSCI_CORP/$SIGSCI_SITE"
  jq -e '.enabled == true' "$TMPD/rule.json" >/dev/null || { printf 'rule %s is already disabled; nothing to do\n' "$id"; return 0; }
  writable_rule < "$TMPD/rule.json" | jq '.enabled = false' > "$TMPD/body.json"
  printf 'target: %s/%s  PUT %s\n' "$SIGSCI_CORP" "$SIGSCI_SITE" "$(site_path "/rules/$id")"
  jq -r '"rule \(.id): \(.reason | .[0:160])\nchange: enabled true -> false (everything else sent back unchanged)"' "$TMPD/rule.json"
  if ! write_allowed; then
    printf 'DRY RUN: nothing sent. To apply, re-run with SIGSCI_ALLOW_WRITE=%s\n' "$SIGSCI_SITE"; return 0
  fi
  local out; out=$(api PUT "$(site_path "/rules/$id")" --data-binary @"$TMPD/body.json") || die "disable failed: $out"
  api GET "$(site_path "/rules/$id")" | jq -r '"rule \(.id) now enabled=\(.enabled) (updated \(.updated))"'
}

cmd_get() {
  load_config
  [ -n "${1:-}" ] || die "get needs a PATH"
  assert_safe_path "$1"; assert_not_secret "$1"
  api GET "$(site_path "$1")"
}

cmd_corp_get() {
  load_config
  [ -n "${1:-}" ] || die "corp-get needs a PATH"
  assert_safe_path "$1"; assert_not_secret "$1"
  api GET "/corps/$SIGSCI_CORP$1"
}

usage() {
  cat <<'USAGE'
ngwaf.sh: Fastly Next-Gen WAF (Signal Sciences) incident client

Setup cache: ~/.config/ngwaf-incident/config (override: NGWAF_CONFIG). No token in it.
  setup (--op op://<vault>/<item>/<field> [--op-account ACCOUNT] | --file PATH [--var NAME])
        --corp CORP --site SITE --user API_USER_EMAIL
                         Record where the token is, then run auth-test. With --file,
                         an env-style file may supply SIGSCI_CORP/SIGSCI_SITE/SIGSCI_EMAIL.
  auth-test              Cheap check of the cached setup. Exit 3 = run setup (no cache),
                         4 = run setup (token unreadable, or API returned 401/403),
                         5 = API or network error (retry).

Read (TIME = unix seconds, -30m, -2h, -1d, or ISO-8601 UTC):
  rules [--json]         Site + corp rules (all pages) and site alerts: each signal, and
                         the block rules and blocking alerts that act on it. Says when
                         coverage is incomplete.
  feed FROM UNTIL        Flagged requests as NDJSON, all pages. UNTIL is moved back to
                         5 min ago if later. Window <= 24h, FROM <= 7 days ago. Exit 2 = truncated.
  timeseries TAG[,TAG] [FROM] [UNTIL] [ROLLUP] [--json]
                         Request counts per signal (e.g. BLOCKED). Default last 1h, 60s.
  search "QUERY" [LIMIT] Flagged-request search; on failure use feed.
  verify-rule ID FROM UNTIL [--host HOST] [--ua REGEX] [--path REGEX]
                         Per-rule effect from the feed: requests the rule tagged, by code,
                         UA, path; blocks by other rules; filter-matching candidates it
                         did not tag. Warns if FROM is before the rule's last change.
  get PATH | corp-get PATH
                         Raw site- or corp-scoped GET. Secret-bearing endpoints refused.

Write (dry run unless SIGSCI_ALLOW_WRITE=<site name>):
  create FILE|-          POST a new site rule (never retried).
  disable ID             PUT the rule back with enabled=false (incident rollback).
USAGE
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  help|-h|--help) usage ;;
  setup) cmd_setup "$@" ;;
  auth-test) cmd_auth_test ;;
  rules) cmd_rules "$@" ;;
  feed) cmd_feed "$@" ;;
  timeseries) cmd_timeseries "$@" ;;
  search) cmd_search "$@" ;;
  verify-rule) cmd_verify_rule "$@" ;;
  create) cmd_create "$@" ;;
  disable) cmd_disable "$@" ;;
  get) cmd_get "$@" ;;
  corp-get) cmd_corp_get "$@" ;;
  *) die "unknown command '$cmd' (see: ngwaf.sh help)" ;;
esac
