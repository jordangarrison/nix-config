# shellcheck shell=bash
# collect.sh — per-source collectors for the day dashboard (sourced, no shebang).
#
# Sourced by day-dashboard.sh. Each `collect_<source>` prints ONE JSON object on
# stdout and NEVER exits non-zero (graceful degradation — one dead source must
# not sink the run):
#
#   { "source": "linear", "available": true,  "items": [ {…} ] }
#   { "source": "linear", "available": false, "reason": "…" }
#
# item shape (all optional except title):
#   { "title": string, "detail": string, "url": string,
#     "priority": "high"|"medium"|"low", "state": string, "when": string }
#
# Data paths (all depend on the user's unlocked login keyring / session bus,
# which is why the job runs as a systemd *user* service, not a system one):
#   * Slack, Linear   → the Pi CLI driving the already-authenticated MCP servers
#                       in $MCP_CONFIG (~/.config/mcp/mcp.json). Tokens live in
#                       Pi's keyring, so no secrets files are needed.
#   * Email, Calendar → the `gws` Google Workspace CLI (keyring-backed).
#   * Confluence      → Atlassian REST with a token file (no MCP server exists).
#
# Any source can be overridden with DAY_DASHBOARD_<SOURCE>_CMD → a command that
# prints {"items":[…]} (or a bare [...]). This is how the collectors are tested
# without live credentials.

# Emit an "unavailable" record. $1=source $2=reason
_unavailable() {
  jq -cn --arg s "$1" --arg r "$2" '{source:$s, available:false, reason:$r}'
}

# Wrap a raw {"items":[…]} (or bare [...]) payload into the standard envelope,
# capping item count. $1=source  stdin=payload
_finalize() {
  local source="$1"
  jq -c --arg s "$source" --argjson max "${DAY_DASHBOARD_MAX_ITEMS:-8}" '
    (if type=="array" then {items:.} else . end)
    | { source:$s, available:true,
        items:( [ (.items // [])[] | select(type=="object") ][:$max] ) }
  ' 2>/dev/null || _unavailable "$source" "collector returned invalid JSON"
}

# Extract the last JSON object from noisy text (model output may add prose).
_extract_obj() {
  node -e 'const s=require("fs").readFileSync(0,"utf8");const i=s.indexOf("{"),j=s.lastIndexOf("}");if(i<0||j<i){process.exit(1)}try{process.stdout.write(JSON.stringify(JSON.parse(s.slice(i,j+1))))}catch{process.exit(1)}'
}

# If DAY_DASHBOARD_<SOURCE>_CMD is set, run it instead of the built-in.
# Returns 0 (handled) or 1 (no override). $1=source
_run_override() {
  local source="$1"
  local var="DAY_DASHBOARD_${source^^}_CMD"
  local cmd="${!var:-}"
  [ -n "$cmd" ] || return 1
  local out
  if out="$(bash -c "$cmd" 2>/dev/null)" && [ -n "$out" ]; then
    printf '%s' "$out" | _finalize "$source"
  else
    _unavailable "$source" "override command failed: $var"
  fi
  return 0
}

_read_secret() {
  local f="$SECRETS_DIR/$1"
  [ -r "$f" ] || return 1
  tr -d '\r\n' <"$f"
}

# Run gws with a hard timeout so one slow/hung Google call can't wedge the run.
_gws() {
  timeout "${DAY_DASHBOARD_GWS_TIMEOUT:-20}" gws "$@"
}

# Run gh with a hard timeout.
_gh() {
  timeout "${DAY_DASHBOARD_GH_TIMEOUT:-30}" gh "$@"
}

# Drive a single MCP server through the Pi CLI. Writes a scoped one-server
# mcp-config so only that server's tools load (cheaper, no rootly/scaleops
# noise). $1=server  $2=instruction  → prints Pi's stdout (expected: a JSON obj)
_pi_mcp() {
  local server="$1" instruction="$2"
  [ -r "$MCP_CONFIG" ] || return 1
  jq -e --arg s "$server" '.mcpServers[$s]' "$MCP_CONFIG" >/dev/null 2>&1 || return 1
  local cfg="$WORK/mcp-$server.json"
  jq -c --arg s "$server" '{mcpServers: {($s): .mcpServers[$s]}}' "$MCP_CONFIG" >"$cfg" 2>/dev/null || return 1
  # `--tools mcp` is an ALLOWLIST: only the MCP tool is enabled. `--no-builtin-tools`
  # is not enough here — the user's Pi config loads extensions (pi-web-access,
  # pi-subagents, ...) whose tools would otherwise stay available, so a
  # prompt-injected Slack/Linear/Rootly response could reach web access, spawn
  # subagents, or hit other MCP servers. The allowlist + the scoped one-server
  # mcp-config keep this to exactly the intended read-only source.
  # A single gather normally finishes in ~60-90s; cap at 120s so three sequential
  # MCP sources stay within the unit's start timeout while one dead server just
  # degrades that source.
  timeout "${DAY_DASHBOARD_MCP_TIMEOUT:-120}" pi -p \
    --no-session --no-skills --no-context-files --no-prompt-templates --no-themes \
    --tools mcp --mcp-config "$cfg" \
    --model "${DAY_DASHBOARD_MCP_MODEL:-openai-codex/gpt-5.6-luna}" --thinking off \
    "$instruction" 2>>"$WORK/collect.err"
}

# ── Linear (via MCP) ────────────────────────────────────────────────────────
collect_linear() {
  _run_override linear && return 0
  local n="${DAY_DASHBOARD_MAX_ITEMS:-8}" out
  if ! out="$(_pi_mcp linear "Use the Linear MCP tools to list up to $n of my active (not done, not canceled) assigned issues, most recently updated first. Output ONLY a JSON object {\"items\":[{\"title\":\"IDENT — title\",\"url\":\"issue url\",\"priority\":\"high|medium|low\",\"state\":\"state name\"}]} and nothing else. If you cannot reach Linear, output {\"items\":[]}.")"; then
    _unavailable linear "linear mcp unavailable (no server in $MCP_CONFIG or Pi/keyring not reachable)"
    return 0
  fi
  printf '%s' "$out" | _extract_obj | _finalize linear \
    || _unavailable linear "linear mcp returned nothing parseable"
}

# ── Slack (via MCP) ─────────────────────────────────────────────────────────
collect_slack() {
  _run_override slack && return 0
  local n="${DAY_DASHBOARD_MAX_ITEMS:-8}" out
  if ! out="$(_pi_mcp slack "Use the Slack MCP tools to find up to $n recent Slack items from the last day: (a) messages that @-mention me or are unread DMs I have NOT answered, and (b) a few recent messages I SENT that answer or acknowledge a request. For type (b), begin the detail with 'ALREADY HANDLED BY ME: ' so a duplicate notification elsewhere can be dropped. Output ONLY a JSON object {\"items\":[{\"title\":\"#channel · sender\",\"detail\":\"message text\",\"url\":\"permalink\"}]} and nothing else. If you cannot reach Slack, output {\"items\":[]}.")"; then
    _unavailable slack "slack mcp unavailable (no server in $MCP_CONFIG or Pi/keyring not reachable)"
    return 0
  fi
  printf '%s' "$out" | _extract_obj | _finalize slack \
    || _unavailable slack "slack mcp returned nothing parseable"
}

# ── Rootly (via MCP) ────────────────────────────────────────────────────────
collect_rootly() {
  _run_override rootly && return 0
  local n="${DAY_DASHBOARD_MAX_ITEMS:-8}" out
  if ! out="$(_pi_mcp rootly "Use the Rootly MCP tools to list up to $n active or ongoing incidents that involve me or need my attention (started/mitigating, not resolved). Output ONLY a JSON object {\"items\":[{\"title\":\"incident title\",\"url\":\"incident url\",\"state\":\"status\"}]} and nothing else. If you cannot reach Rootly, output {\"items\":[]}.")"; then
    _unavailable rootly "rootly mcp unavailable (no server in $MCP_CONFIG or Pi/keyring not reachable)"
    return 0
  fi
  printf '%s' "$out" | _extract_obj | _finalize rootly \
    || _unavailable rootly "rootly mcp returned nothing parseable"
}

# ── GitHub (via gh CLI) → only high-signal PRs ────────────────────────────
# GitHub is very high-volume, so the collector only pulls PRs requesting my
# review or @-mentioning me; the synthesis model then keeps just the
# architecture / infrastructure / playbook-relevant ones. gh uses its file auth
# (~/.config/gh/hosts.yml), so no GITHUB_TOKEN env is required in the service.
collect_github() {
  _run_override github && return 0
  command -v gh >/dev/null 2>&1 || { _unavailable github "gh CLI not on PATH"; return 0; }
  local n="${DAY_DASHBOARD_GITHUB_MAX:-14}" since rr men
  since="$(date -u -d "${DAY_DASHBOARD_GITHUB_SINCE:-3 days ago}" +%Y-%m-%d 2>/dev/null)"
  rr="$(_gh search prs --review-requested=@me --state=open --limit "$n" \
    --json title,url,repository,updatedAt,isDraft 2>/dev/null)"
  men="$(_gh search prs --mentions=@me --state=open --updated=">=$since" --limit "$n" \
    --json title,url,repository,updatedAt,isDraft 2>/dev/null)"
  printf '%s' "$rr" | jq -e . >/dev/null 2>&1 || rr='[]'
  printf '%s' "$men" | jq -e . >/dev/null 2>&1 || men='[]'
  jq -cn --argjson rr "$rr" --argjson men "$men" --argjson max "$n" '
    ([ $rr[]? | . + {reason:"review requested"} ] + [ $men[]? | . + {reason:"mentioned"} ])
    | map(select((.isDraft // false) | not))
    | unique_by(.url)
    | { source:"github", available:true, items: ( map({
        title:(.title // "(pr)"),
        url:(.url // ""),
        detail:(((.repository.nameWithOwner // "?")) + " · " + (.reason // "")),
        when:(.updatedAt // "")
      }) | .[:$max] ) }' 2>/dev/null \
    || _unavailable github "could not parse github response"
}

# ── Email (via gws / Gmail) ──────────────────────────────────────────────────
collect_email() {
  _run_override email && return 0
  command -v gws >/dev/null 2>&1 || { _unavailable email "gws CLI not on PATH"; return 0; }
  local n="${DAY_DASHBOARD_MAX_ITEMS:-8}" ids
  if ! ids="$(_gws gmail users messages list \
      --params "{\"userId\":\"me\",\"q\":\"is:unread in:inbox\",\"maxResults\":$n}" 2>/dev/null \
      | jq -r '.messages[]?.id' 2>/dev/null)"; then
    _unavailable email "gmail list failed (is the login keyring unlocked?)"
    return 0
  fi
  : >"$WORK/email.items"
  local id
  while read -r id; do
    [ -n "$id" ] || continue
    _gws gmail users messages get \
      --params "$(jq -cn --arg id "$id" '{userId:"me", id:$id, format:"metadata", metadataHeaders:["From","Subject"]}')" 2>/dev/null \
      | jq -c --arg id "$id" '
          (.payload.headers // []) as $h
          | ([$h[]|select(.name=="From")|.value][0] // "?") as $fromRaw
          | ([$h[]|select(.name=="Subject")|.value][0] // "(no subject)") as $subj
          # Prefer the display name; fall back to the bare address. Strips the
          # ugly "Name" <addr> header form so titles read like a person.
          | ($fromRaw | sub("\\s*<[^>]*>$";"") | sub("^\"";"") | sub("\"$";"")) as $from
          | { title: ($from + " — " + $subj),
              detail: $subj,
              url: ("https://mail.google.com/mail/u/0/#all/" + $id) }' 2>/dev/null \
      >>"$WORK/email.items" || true
  done <<<"$ids"
  jq -cs '{items: .}' "$WORK/email.items" 2>/dev/null | _finalize email \
    || _unavailable email "could not assemble gmail items"
}

# ── Calendar (via gws / Google Calendar) ────────────────────────────────────
collect_calendar() {
  _run_override calendar && return 0
  command -v gws >/dev/null 2>&1 || { _unavailable calendar "gws CLI not on PATH"; return 0; }
  local tmin tmax resp
  tmin="$(date -d 'today 00:00' +%Y-%m-%dT%H:%M:%S%:z)"
  tmax="$(date -d 'tomorrow 00:00' +%Y-%m-%dT%H:%M:%S%:z)"
  if ! resp="$(_gws calendar events list \
      --params "{\"calendarId\":\"primary\",\"timeMin\":\"$tmin\",\"timeMax\":\"$tmax\",\"singleEvents\":true,\"orderBy\":\"startTime\",\"maxResults\":${DAY_DASHBOARD_MAX_ITEMS:-8}}" 2>/dev/null)"; then
    _unavailable calendar "calendar list failed (is the login keyring unlocked?)"
    return 0
  fi
  # Emit start/end (RFC3339 with local offset) and allDay so the renderer can
  # draw the day as terrain and place a "now" marker. `when` stays for display.
  printf '%s' "$resp" | jq -c '{items: [ .items[]? | {
      title: (.summary // "(busy)"),
      start: ((.start.dateTime // .start.date) // ""),
      end: ((.end.dateTime // .end.date) // ""),
      allDay: (.start.dateTime == null),
      when: ((.start.dateTime // .start.date) // ""),
      url: (.htmlLink // "")
    } ]}' 2>/dev/null | _finalize calendar \
    || _unavailable calendar "could not parse calendar response"
}

# ── Meeting notes (via gws / Google Docs) → my action items ─────────────────
# Finds recently-modified Google Docs (Google Meet "Notes by Gemini" and the
# like), exports each to text, and pulls the lines that are follow-ups assigned
# to me. Gemini notes tag owners as "[Full Name]", which is a precise anchor.
collect_notes() {
  _run_override notes && return 0
  command -v gws >/dev/null 2>&1 || { _unavailable notes "gws CLI not on PATH"; return 0; }
  local me="${DAY_DASHBOARD_ME:-Jordan Garrison}"
  # Notes docs are exported one by one (each up to a few hundred KB), so cap
  # them tighter than other sources to keep the hourly run brisk.
  local n="${DAY_DASHBOARD_NOTES_DOCS:-4}" since list rows
  since="$(date -u -d "${DAY_DASHBOARD_NOTES_SINCE:-2 days ago}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  local q="mimeType='application/vnd.google-apps.document' and modifiedTime > '$since' and trashed=false"
  if ! list="$(_gws drive files list \
      --params "$(jq -cn --arg q "$q" --argjson n "$n" '{q:$q, orderBy:"modifiedTime desc", pageSize:$n, fields:"files(id,name,modifiedTime,webViewLink)"}')" 2>/dev/null)"; then
    _unavailable notes "drive list failed (is the login keyring unlocked?)"
    return 0
  fi
  : >"$WORK/notes.items"
  rows="$(printf '%s' "$list" | jq -c '.files[]?' 2>/dev/null)" || rows=""
  local row id name url when mine
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    id="$(printf '%s' "$row" | jq -r '.id // empty')"
    [ -n "$id" ] || continue
    name="$(printf '%s' "$row" | jq -r '.name // "(untitled doc)"')"
    url="$(printf '%s' "$row" | jq -r '.webViewLink // ""')"
    when="$(printf '%s' "$row" | jq -r '.modifiedTime // ""')"
    # gws --output sandboxes to the working directory, so export from inside
    # $WORK (subshell keeps the orchestrator's cwd untouched).
    ( cd "$WORK" && _gws drive files export \
        --params "$(jq -cn --arg id "$id" '{fileId:$id, mimeType:"text/plain"}')" \
        --output note.txt ) >/dev/null 2>&1 || continue
    # Precise: Gemini owner tag "[Full Name]". Fallback: my name near an
    # action verb. Only docs with a follow-up owned by me are kept.
    mine="$(grep -iF "[$me]" "$WORK/note.txt" 2>/dev/null | head -6)"
    [ -n "$mine" ] || mine="$(grep -iF "$me" "$WORK/note.txt" 2>/dev/null \
      | grep -iE 'follow up|action|draft|write|contact|send|prepare|schedule|by (mon|tue|wed|thu|fri|next|end)' | head -4)"
    [ -n "$mine" ] || continue
    printf '%s' "$mine" | jq -Rs --arg t "$name" --arg u "$url" --arg w "$when" \
      '{title:$t, detail:(.[0:600]), url:$u, when:$w}' >>"$WORK/notes.items" 2>/dev/null || true
  done <<<"$rows"
  jq -cs '{items: .}' "$WORK/notes.items" 2>/dev/null | _finalize notes \
    || _unavailable notes "could not assemble notes items"
}

# ── Confluence (Atlassian Cloud REST, CQL) ──────────────────────────────────
# No Confluence MCP server exists, so this keeps a token-file REST collector.
collect_confluence() {
  _run_override confluence && return 0
  local base="${DAY_DASHBOARD_CONFLUENCE_BASE:-}"
  local creds
  if [ -z "$base" ]; then
    _unavailable confluence "no base url (set DAY_DASHBOARD_CONFLUENCE_BASE=https://<site>.atlassian.net/wiki)"
    return 0
  fi
  if ! creds="$(_read_secret atlassian)"; then
    _unavailable confluence "no credentials (create $SECRETS_DIR/atlassian with 'email:api-token')"
    return 0
  fi
  # Pass credentials via a 0600 curl config file, not `-u` on the command line,
  # so the email:token pair never appears in /proc/<pid>/cmdline (this host has
  # other local accounts).
  local resp curlcfg="$WORK/atlassian.curl"
  ( umask 077; printf 'user = "%s"\n' "$creds" >"$curlcfg" )
  if ! resp="$(curl -fsS --max-time 25 --config "$curlcfg" -G "$base/rest/api/content/search" \
      -H "Accept: application/json" \
      --data-urlencode "cql=contributor = currentUser() order by lastmodified desc" \
      --data-urlencode "limit=${DAY_DASHBOARD_MAX_ITEMS:-8}" \
      --data-urlencode "expand=version" 2>/dev/null)"; then
    _unavailable confluence "confluence api request failed"
    return 0
  fi
  printf '%s' "$resp" | jq -c --arg base "$base" '{items: [ .results[]? | {
      title: (.title // "(untitled)"),
      when: (.version.when // ""),
      url: ($base + (._links.webui // ""))
    } ]}' 2>/dev/null | _finalize confluence \
    || _unavailable confluence "could not parse confluence response"
}
