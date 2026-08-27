# day-dashboard

A low-cost, private, hourly personal day/work dashboard. It gathers actionable
context (calendar, email, Slack, Linear, Confluence), asks the Pi CLI for a
prioritized briefing, and renders a static HTML page. It degrades gracefully per
source and preserves the last good page on failure.

See `docs/adr/006-hourly-day-dashboard.md` for the design rationale.

## The page

Adapted from a personal "morning brief", tuned for a page that refreshes through
the day rather than once at dawn:

- a warm two-band layout with a serif (Fraunces) headline written **for the
  current moment** ("The evening is open now.");
- a hand-drawn SVG **terrain of the day** — elevation tracks meeting load, dots
  are meetings (past ones dimmed), and a clay **"now" marker** slides across as
  the day progresses (the continuous-refresh signature);
- three **acts** (morning / midday / evening) with time ranges and a sentence each;
- two calm lists — **Needs attention** and **Resolved** — each item a bold
  linked title plus one observational sentence with the source named inline;
- a `<details>` with the raw per-source data for transparency.

The terrain and day classification are computed deterministically from the
calendar; the model only writes the words. All links open in a new tab. The page
auto-reloads every 15 min (`<meta refresh>`) and is regenerated hourly by the
timer. Fraunces is base64-embedded (no network); it falls back to Georgia.

### Action threads (grouping + ticket tracking)

Actions are grouped by whatever **triggered** them — a meeting's notes, a Linear
epic, a Slack thread, an email chain, a Rootly incident, a support ticket — and
each group is a collapsible section (`kind · origin · N, M tracked`). The model
cross-references every action item against the Linear issues already in context:
if the work is already ticketed it shows the ticket link and status `tracked`
instead of re-nagging; otherwise it is `open`. Standalone asks (a single
blocking email/Slack message, prep for a meeting soon) stay in **Needs
attention**.

### Cross-source correlation (noise removal)

The same real-world thing often notifies you in several places (an email *and* a
Slack message *and* a Linear ticket). The synthesis model correlates across all
sources by person / subject / ticket-or-PR id and (a) merges duplicates into one
item linking each source, and (b) **drops** anything already handled elsewhere
— e.g. a time-off-request email you already answered in Slack. The Slack
collector also captures a few of *your own* recent replies (marked `ALREADY
HANDLED BY ME`) so the model can tell what you've dealt with.

### Dismissing noise (the ✕ links)

Every `needsAttention` and action item has a small **✕** link. Clicking it hits
a tiny localhost handler (`day-dashboard-dismiss` user service, proxied at
`/dismiss` on the private vhost), which records the item's stable key in
`dismissed.json`, **re-renders the page instantly** from the last run's
persisted inputs, and redirects back — so the item disappears on click, not an
hour later. Every future render filters dismissed keys out. Dismissals persist
(30-day prune); if the underlying item materially changes (new title) its key
changes and it can reappear. Undo by hitting `/undismiss?k=<key>`; inspect with
`GET /dismissed`. The handler binds to 127.0.0.1 and only ever reads/writes JSON
and re-runs the renderer — no shell, no user input executed.

### Caching (fewer tokens, and a tracking ledger)

`<stateDir>/cache.json` (not served) holds three things:

- **TTL cache** for the token-costly MCP collectors (Slack/Linear/Rootly),
  default 120 min (`DAY_DASHBOARD_MCP_TTL_MIN`). `gws`/Confluence are free so
  they always re-fetch. So the slow full collect happens ~once every couple of
  hours; most hourly runs reuse those results.
- **Synthesis skip**: the collected context is fingerprinted; if it is unchanged
  from the last run (and the cached briefing is younger than
  `DAY_DASHBOARD_BRIEF_MAX_MIN`, default 360), the model call is skipped entirely
  and the page is just re-rendered (new time + "now" marker). A quiet hour costs
  **zero** model tokens.
- **Item ledger**: every grouped action item is remembered (first/last seen,
  status, ticket) so we know what is already tracked and what is new — the
  foundation for future update notifications. `status.json` reports
  `trackedFollowups`. Set `DAY_DASHBOARD_NO_CACHE=1` to bypass it all.

## Pipeline

```
collectors  →  bounded context JSON  →  pi -p (cheap model)  →  render.mjs  →  index.html
   per source        available only        briefing JSON          escaped HTML     atomic publish
```

Where the data comes from (all keyring-backed, hence a **user** service):

| Source | How it's gathered |
| --- | --- |
| **Slack**, **Linear**, **Rootly** | the Pi CLI driving the already-authenticated MCP servers in `~/.config/mcp/mcp.json` (tokens live in Pi's keyring) |
| **Email**, **Calendar** | the `gws` Google Workspace CLI (Gmail unread + today's events) |
| **Meeting notes** | `gws`/Google Docs — recent "Notes by Gemini" docs; extracts follow-ups/action items assigned to you (Gemini tags owners as `[Full Name]`) and the model turns them into concrete next actions |
| **GitHub** | the `gh` CLI (file auth) — PRs review-requested-from or @-mentioning you; the model keeps only architecture/infra/deploy-relevant ones and flags changes that may deviate from the playbooks (playbooks.flokubernetes.com). Deliberately NOT everything — GitHub is high-volume. |
| **Confluence** | Atlassian REST with a token file (no Confluence MCP server exists) |

- `day-dashboard.sh` — orchestrator (also runnable by hand)
- `lib/collect.sh` — per-source collectors
- `lib/render.mjs` — dependency-free, injection-safe HTML renderer (unit-tested)
- `lib/prompt.md` — system prompt for the briefing model
- `test/render.test.mjs` — `node --test` suite (runs as a build gate)

## Run by hand

Because Slack/Linear (MCP) and email/calendar (`gws`) read the login keyring,
run it from inside your graphical session (where the keyring is unlocked):

```bash
DAY_DASHBOARD_STATE_DIR=/tmp/dd day-dashboard
xdg-open /tmp/dd/www/index.html

# subset of sources
DAY_DASHBOARD_STATE_DIR=/tmp/dd DAY_DASHBOARD_SOURCES="calendar email linear" day-dashboard

# skip the synthesis model (raw sources only)
DAY_DASHBOARD_STATE_DIR=/tmp/dd DAY_DASHBOARD_SKIP_MODEL=1 day-dashboard

# fake a source without hitting anything (used by the tests)
DAY_DASHBOARD_STATE_DIR=/tmp/dd \
  DAY_DASHBOARD_LINEAR_CMD='echo "{\"items\":[{\"title\":\"ENG-1 fix\",\"priority\":\"high\",\"url\":\"https://linear.app/x\"}]}"' \
  day-dashboard
```

Run the tests:

```bash
cd packages/day-dashboard && node --test test/render.test.mjs
```

## On endeavour

Two modules cooperate:

- **`modules/nixos/day-dashboard.nix`** (system) — state dirs + a **private**
  nginx vhost `day.jordangarrison.dev` serving `/var/lib/day-dashboard/www`,
  restricted to localhost + Tailscale + LAN, with an ACME cert. Enabled via
  `services.day-dashboard.enable = true`.
- **`modules/home/day-dashboard`** (Home Manager) — the generator as a systemd
  **user** service + timer (`*-*-* 06..21:00:00`). It runs as a user service on
  purpose: the collectors need the unlocked login keyring for the Pi MCP tokens
  and `gws`. Enabled via `services.day-dashboard.enable = true` in the user's
  home config.

```bash
systemctl --user start day-dashboard.service      # refresh now
journalctl --user -u day-dashboard.service -f      # watch
systemctl --user list-timers day-dashboard.timer   # next run
cat /var/lib/day-dashboard/www/status.json         # last success + per-source state
```

### Session dependency

The generator only gathers live data while you are logged into the graphical
session (that is what unlocks the keyring). Outside a session it still runs and
publishes, but the keyring-backed sources degrade to "unavailable" rather than
failing the page. The timer is `Persistent`, so a missed slot fires on the next
login.

## Configuration

**System module** (`services.day-dashboard`, NixOS):

| Option | Default |
| --- | --- |
| `host` | `day.jordangarrison.dev` (keep tailnet-only) |
| `allowedRanges` | localhost + `100.64.0.0/10` + RFC1918 |
| `stateDir` | `/var/lib/day-dashboard` |

**Generator** (`services.day-dashboard`, Home Manager):

| Option | Default |
| --- | --- |
| `model` (synthesis) | `openai-codex/gpt-5.6-sol` - stronger, merges related items |
| `mcpModel` (collectors) | `openai-codex/gpt-5.6-luna` - cheap extraction |
| `sources` | `[calendar email slack linear confluence]` |
| `schedule` | `*-*-* 06..21:00:00` |
| `mcpConfig` | `~/.config/mcp/mcp.json` |
| `environment` | `{}` (e.g. Confluence base URL) |

## Credentials

Slack, Linear, email, and calendar need **nothing committed** — they reuse the
OAuth tokens already in your Pi keyring (Slack/Linear MCP) and your `gws` Google
login. Just make sure those are set up:

- **Slack / Linear**: the MCP servers in `~/.config/mcp/mcp.json` must have been
  authenticated once interactively (`pi` runs the OAuth flow on first use). Verify:
  `pi -p --mcp-config ~/.config/mcp/mcp.json 'List one of my Linear issues via MCP'`.
- **Email / Calendar / Meeting notes**: `gws` must be logged in (`gws gmail
  users messages list ...` should return data). Meeting-note action items look
  for lines owned by `DAY_DASHBOARD_ME` (default "Jordan Garrison") in recent
  Google Docs.

An interactive **skill** (`users/jordangarrison/skills/day-dashboard`) wraps this
for on-demand refresh/preview via any agent (`/day`).

Only **Confluence** uses a file, and only if you want it:

| File / env | How to get it |
| --- | --- |
| `secrets/atlassian` = `email:api-token` **and** `DAY_DASHBOARD_CONFLUENCE_BASE` | Atlassian → Account → Security → API tokens; set e.g. `DAY_DASHBOARD_CONFLUENCE_BASE=https://flocasts.atlassian.net/wiki` in `services.day-dashboard.environment` |

```bash
# write the Confluence secret (never commit it)
install -d -m700 /var/lib/day-dashboard/secrets
printf '%s' 'you@flosports.tv:atlassian_api_token' > /var/lib/day-dashboard/secrets/atlassian
chmod 600 /var/lib/day-dashboard/secrets/atlassian
```

### Custom collector override

Any built-in can be replaced with a command that prints `{"items":[…]}` (or a
bare `[…]`), via `DAY_DASHBOARD_<SOURCE>_CMD`. This is how the collectors are
tested without live credentials.

## DNS setup (required for the vhost, not automated)

Create a tailnet-only A record so the page is only reachable inside the tailnet:

```bash
flarectl dns create --zone jordangarrison.dev --name day \
  --type A --content 100.118.65.11 --ttl 1
```

The TLS cert is issued via ACME DNS-01 (Cloudflare) and does not require public
reachability.

## Security notes

- Every string rendered into the page is HTML-escaped; only `http(s)` URLs
  become links. Enforced by `render.mjs`, covered by the build-time test suite
  (which includes explicit XSS/injection cases).
- MCP gathering runs Pi with `--no-builtin-tools`, so the model can only talk to
  the one scoped MCP server — no `bash`/`edit`/`write` on the host.
- The vhost sends `X-Robots-Tag: noindex, nofollow` and `Cache-Control: no-store`.
- No secrets are committed; the only credential file is the optional Confluence one.
```
