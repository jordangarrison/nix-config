# ADR 006: Hourly Personal Day Dashboard

## Status

Accepted

## Date

2026-08-26

## Context

I want a single private page that answers "what should I focus on right now?"
by pulling together actionable work context — Slack mentions, my active Linear
issues, recently-touched Confluence pages, and (where available) email — and
refreshing it automatically through the working day. It should be cheap to run,
degrade gracefully when a source is unavailable, never leak work data publicly,
and never replace a good page with a broken one.

### Constraints / requirements

1. **Low cost** — minimal model, no tools, tiny bounded context per run.
2. **Graceful degradation** — one dead/unconfigured source must not sink the run.
3. **No public leakage** — the page contains work data; it must be private.
4. **Preserve last good page** — a failed run keeps the previous output.
5. **Uses the Pi runtime** already managed in this repo.
6. **Runs headless** on endeavour on a schedule (06:00–21:00, hourly).

## Decision

A small job (`packages/day-dashboard`) with a three-stage pipeline:

1. **Collect** — per-source Bash collectors (`lib/collect.sh`) emit a normalized
   JSON envelope. Slack and Linear are gathered by driving the Pi CLI against
   the already-authenticated **MCP servers** in `~/.config/mcp/mcp.json`; email
   and calendar via the **`gws`** Google Workspace CLI; Confluence via Atlassian
   REST (no MCP server exists). Every collector always emits valid JSON and
   never exits non-zero; an unreachable source yields `{available:false,
   reason}` instead of an error.
2. **Summarize** — the bounded context of *available* sources is handed to the
   Pi CLI (`pi -p`) with a cheap model, `--no-tools`, thinking off, and all
   resource discovery disabled, to produce a prioritized briefing JSON.
3. **Render** — a dependency-free Node renderer (`lib/render.mjs`) turns the
   collected data (source of truth) plus the optional briefing into static HTML,
   HTML-escaping every string and allowing only `http(s)` URLs.

Two modules cooperate: `modules/nixos/day-dashboard.nix` (system) owns the
state dirs + a **private** nginx vhost + ACME cert; `modules/home/day-dashboard`
(Home Manager) runs the generator as a systemd **user** service + timer
(`06..21:00:00`).

## Architecture decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Pi integration | Drive the installed `pi` **CLI** in print mode (`pi -p`), not `import @earendil-works/pi-coding-agent` | The Nix `pi` package ships as a compiled bun binary with no importable `dist/`; vendoring the npm SDK would add a heavy, network-dependent dependency closure. The SDK docs explicitly bless CLI/subprocess integration ("use the CLI directly"). |
| Two-tier models | Cheap `openai-codex/gpt-5.6-luna` extracts each source; stronger `openai-codex/gpt-5.6-sol` does the final aggregation/prioritization | Gathering is many calls (keep them cheap); synthesis is one cached call where intelligence pays off — e.g. merging several notifications about the same issue into one item with links to all. Both already authenticated in `~/.pi/agent/auth.json`; `claude-bridge/claude-opus-5` also works for synthesis. |
| **System vs user service** | Run the generator as a **systemd user service**, not a system one | Slack/Linear (Pi MCP OAuth) and email/calendar (`gws`) store their tokens in the **login keyring**, which only exists inside the graphical session. A bare `User=` system unit can't reach it (verified: unsetting `DBUS_SESSION_BUS_ADDRESS` makes Linear MCP return `NO_ACCESS`). The user service inherits the session bus + unlocked keyring; the system module keeps only the vhost/dirs/ACME. |
| Slack/Linear gathering | Drive the existing MCP servers via a scoped `pi --mcp-config` call with `--no-builtin-tools` | Reuses the repo's already-authenticated OAuth (no new tokens/secrets), and `--no-builtin-tools` leaves only the one scoped MCP tool — the model can't touch `bash`/`edit`/`write`. MCP OAuth is browser-interactive on first use but headless thereafter. |
| Email/calendar gathering | `gws` CLI (deterministic) | Google has no MCP server here; `gws` is already installed and keyring-authenticated, and needs no model tokens. |
| Data flow | Collectors gather; the synthesis model only prioritizes | Keeps raw data accurate even if the model hallucinates or is skipped. |
| HTML safety | Deterministic render from validated JSON, escape everything, scheme-filter URLs | The model/collector text is untrusted; escaping is what prevents work data from becoming active content. Unit-tested as a build gate. |
| Failure policy | Model failure → render raw-only page (still useful); render/empty failure → keep last good page (atomic publish) | Matches "degrade gracefully" and "preserve last good page". |
| Privacy | ACME (DNS-01) cert + tailnet-only A record + nginx `allow`/`deny` guard | endeavour's host firewall is disabled, so DNS-to-Tailscale plus an explicit allow list (localhost, `100.64.0.0/10`, RFC1918) is defense in depth. `X-Robots-Tag: noindex` and `Cache-Control: no-store` for good measure. |
| Credentials | Optional files under `/var/lib/day-dashboard/secrets` (0700), read at runtime | Truly optional (no `LoadCredential` hard failure); nothing secret is committed. |

## Consequences

- With no credentials configured the dashboard still builds, deploys, and serves
  a valid page listing which sources need setup — so it ships useful on day one.
- Adding a source is a matter of dropping a credential file (or setting a
  `DAY_DASHBOARD_<SRC>_CMD` override); no rebuild needed for the built-ins.
- The model call is the only recurring cost and is intentionally tiny.
- Because it is a user service, live data is only gathered while logged into the
  graphical session; outside a session it still publishes, with keyring-backed
  sources degrading to "unavailable". The timer is `Persistent`.
- Slack, Linear, email, and calendar need nothing committed (they reuse existing
  Pi-keyring and `gws` auth). Only Confluence uses an optional token file.

## Cross-source correlation & GitHub

- **Correlation / noise removal**: one request often notifies across email,
  Slack, Linear, and GitHub. The synthesis model correlates by person / subject
  / ticket-or-PR id, merges duplicates into one item (all urls in `links`), and
  *drops* anything already handled elsewhere — e.g. a time-off email answered in
  Slack. To give it that signal, the Slack collector also pulls a few of the
  user's own recent replies, marked `ALREADY HANDLED BY ME`.
- **GitHub** (via `gh`, file auth) is deliberately narrow: only
  review-requested / @-mention PRs are collected, and the model keeps just the
  architecture / infrastructure / deploy-relevant ones — flagging changes that
  may deviate from the playbooks at `playbooks.flokubernetes.com`. GitHub is far
  too high-volume to surface wholesale.

## Dismissing noise

The page is static, so a click needs an endpoint. Each item carries a stable key
(`sha1(source|title)`) and a **✕** link to `/dismiss?k=<key>`, proxied on the
private vhost to a tiny localhost handler (a Home Manager user service). The
handler records the key in `dismissed.json`, re-renders `index.html` instantly
from the last run's persisted inputs (no re-collection, no model), and 302s
back — so dismissal is immediate. Every render filters dismissed keys. This is
the general answer to "I already handled it elsewhere" when no collector can see
the handling (e.g. a HiBob time-off approval done via a Slack button): the user
dismisses it once and it stays gone.

## Grouping, tickets, and caching

- **Action threads**: actions are grouped by their originating trigger (meeting
  notes, a Linear epic, a Slack thread, an email chain, a Rootly incident, a
  support ticket), rendered as collapsible groups. The synthesis model
  cross-references each item against the Linear issues already in context and
  marks it `ticketed` (with the ticket link) or `open` — so already-created
  tickets are tracked, not re-nagged.
- **Cache** (`<stateDir>/cache.json`, never served): a TTL cache for the
  token-costly MCP collectors (Slack/Linear/Rootly, 120 min) while free `gws`
  sources stay fresh; a context **fingerprint** that skips the synthesis model
  call outright on an unchanged hour (zero tokens); and an **item ledger**
  (first/last seen, status, ticket) that records what is already tracked — the
  basis for future update notifications.
- **Collection is sequential**, not parallel: the MCP collectors share one model
  provider that serializes concurrent sessions, so parallelism only slowed each
  call and risked rate-limits. The unit timeout is 10 min for the occasional
  cold full collect; the cache keeps steady-state runs short.

## Presentation

The page is adapted from a personal "morning brief": a warm two-band layout, a
Fraunces serif headline, a deterministic SVG **terrain** of the day (elevation =
meeting load) carrying a clay **"now" marker**, three acts, and calm Needs
attention / Resolved lists. Because it refreshes hourly rather than once, the
headline is written for the current moment and the marker moves through the day.
The terrain/classification are computed from the calendar (deterministic); the
model only writes words. Fraunces (`pkgs.fraunces`, ~64KB TTF) is base64-embedded
— no network, Georgia fallback.

## Remaining setup (not automated)

- **DNS**: `day.jordangarrison.dev` A → `100.118.65.11` (Tailscale). *(Done.)*
- **Confluence** (optional): base URL is wired in `flake.nix`
  (`flocasts.atlassian.net/wiki`); still needs a `secrets/atlassian`
  (`email:api-token`) file — see `packages/day-dashboard/README.md`.
- Slack/Linear/email/calendar need nothing beyond the already-authenticated Pi
  MCP servers and `gws` login.

## References

- Pi SDK docs: `${pi}/libexec/pi/docs/sdk.md`, examples in `.../examples/sdk/`
- `packages/day-dashboard/README.md`
