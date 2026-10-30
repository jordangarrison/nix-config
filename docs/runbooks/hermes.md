# Hermes personal coding agent

Not deployed. No host enables `services.hermes` or `hermes-desktop`.
The module, tests, and this runbook remain so the service can be turned
back on. Do not treat the steps below as the live setup.

When it was deployed, Hermes ran on `endeavour` with the stock web dashboard:

- `hermes-serve`: runs `hermes dashboard --isolated --no-open --skip-build`
  on `127.0.0.1:9119`, supervised by systemd. Despite the retained unit name,
  this is the standard dashboard, **not** the headless `hermes serve` command.
- `hermes-gateway`: the optional Slack gateway for **JordanBot**
  ([Slack](#slack-jordanbot)). It stays inactive until the OAuth state and the
  root-owned `jordanbot-enabled` marker exist. The dashboard does not depend on it.

Open **https://hermes.jordangarrison.dev/chat** in a browser on the tailnet.
Sign in with the existing dashboard username/password (instructions below).
This serves the stock UI and the API used by Conduit/Desktop directly; there
is no custom discovery proxy or exposed canonical shared-owner API.

### Why not expose the shared gateway?

In the pinned Hermes 0.22.5, the canonical API rejects requests sent by both
Conduit and the bundled web UI: Conduit's `session.create` sends
`source: "desktop"` and `cols`; its fallback resume sends `inline_images`;
the web side panel sends `close_on_disconnect`. The standard dashboard accepts
these requests. Regression checks exercise these actual client payloads.
Do not replace the dashboard with the canonical gateway just because an API
ping or a hand-written model request passes.

Sharing a profile shares stored history and credentials, **not** guaranteed
simultaneous ownership of a live terminal chat. Conduit's takeover plugin
refuses a live classic CLI claim even when idle, because it cannot verify that
no turn is running. Finish the turn and close the terminal chat before opening
it elsewhere. Desktop/TUI takeover has separate constraints; test the actual
client workflow before promising seamless handoff. Normal upstream terminal
clients may manage their own runtime. In particular, opening the dashboard's
embedded terminal can start an upstream runtime as a child of `hermes-serve`.
The UI may then report “Gateway Running” even while the gated Slack systemd
unit remains inactive. That is normal upstream behavior; the public endpoint
still serves the standard dashboard contract, not the canonical API.

Both units use the published `pkgs.llm-agents.hermes-agent` package, the same work
OpenAI **Codex OAuth** grant, and `/home/jordangarrison/.local/share/hermes-service` state. Desktop is an
optional client, not a supervisor: closing it does not stop either service.
No desktop login, SSH session, public application endpoint, or new firewall rule
is needed. Public DNS names a private Tailscale IP, not a public ingress.
The `platforms.api_server` setting remains disabled: that is Hermes's separate
OpenAI-compatible API platform, not the Desktop `serve` endpoint.

Both services run as **jordangarrison**, not a dedicated service account. Hermes
and its plugins can access Jordan's repositories, user credentials and groups.
The normal upstream CLI/Slack/cron tool bundles are enabled: terminal, files,
search, skills, delegation, and available integrations; Conduit tools are no
longer suppressed. This is deliberately a personal coding agent, not an isolated
chat bot. Use a VM if a separate trust boundary is wanted later.

The system units deliberately run without an additional service sandbox, with
Jordan's normal filesystem, device, network, group, and existing sudo access.
They do not run as root or grant new passwordless sudo rules. Sudo authentication
still follows the host's policy; a noninteractive session may need operator
authentication. Private file creation (`UMask=0077`), dashboard authentication,
Slack allowlisting, and tailnet ingress restrictions remain in place.
No new sudo privileges, scheduled jobs, or Grokbot cutover are configured.

## Ownership and paths

Hermes owns its configuration; Nix owns the service around it.

- `modules/nixos/hermes.nix`: service identity, units, the config seed and pins,
  tool selection.
- `hosts/endeavour/configuration.nix`: enablement, model, Slack member
  allowlist, the Slack gate and the first config's Slack settings.
- `/home/jordangarrison/.local/share/hermes-service/config.yaml`: **Hermes-owned**
  live config. Edit it from the dashboard or Desktop (or `hermes-service config
  set`). Nix seeds it once and keeps only the pinned settings below.
- `/home/jordangarrison/.local/share/hermes-service/.env`: Hermes-owned `0600`
  secrets, including JordanBot's `SLACK_BOT_TOKEN` and `SLACK_APP_TOKEN`.
  Desktop's Slack page writes here. Values here override the unit's defaults
  (such as `SLACK_ALLOWED_USERS`).
- `/home/jordangarrison/.local/share/hermes-service/SOUL.md`: the bot's identity
  and standing instructions, Hermes-owned and editable in Desktop.
- `/etc/hermes-service/config.yaml`: the **seed**, for reference.
  `/etc/hermes-service/pinned.json`: what Nix keeps in the live config.
  `/etc/hermes-service/profiles.json`: both, as applied by `hermes-profiles`.
- `/home/jordangarrison/.local/share/hermes-service`: private mutable sessions,
  memory, and OAuth state; `auth.json` is the Hermes-owned OAuth grant/pool.
- `/var/lib/hermes-secrets/jordanbot-enabled`: root-owned gate; the gateway
  starts only while it exists.
- `/var/lib/hermes-secrets/jordanbot-environment`: the root-only copy the
  JordanBot tokens were first provisioned to. No longer loaded; kept as a backup
  until you delete it. The retired Hermes Pilot app's `environment`/`enabled`
  are gone from this host; revoke that app in Slack separately.
- `/var/lib/hermes-secrets/desktop-environment`: root-owned `0600`
  dashboard username, random password, and persistent signing secret. Loaded
  into the dashboard and the gateway. Separate from OpenAI OAuth.
- `/home/jordangarrison/.local/share/hermes-service/desktop-session-token`: legacy localhost-only credential;
  ignored and rejected when `desktop.publicHost` enables remote authentication.

### Seed and pins

`hermes-profiles` (a oneshot unit, before the dashboard and gateway, at boot and
on every activation that changes it):

- **Seeds** `config.yaml` from `/etc/hermes-service/config.yaml` when the home
  has none, or still links to an earlier Nix-generated file. A regular file is
  never replaced: after the first run, the config is Hermes's.
- **Pins** these leaves in the live config, restoring any that drift:
  `mcp_servers.<name>` (from `programs.mcp`), `skills.external_dirs`,
  `agent.system_prompt` (AGENTS.md), `dashboard.public_url` (the remote-auth
  gate), `auth.adopt_external_logins`. Fields you add beside a pinned leaf
  (e.g. a `tools` filter on an Executor server) stay. A rewrite first saves the
  previous file to `backups/config/config.yaml.pre-nix.<time>`.
- Records what it pinned in `.nix-hermes-profile.json`. Removing a pin from
  Nix removes that leaf, unless it was edited since; then it is left.
- Reports a symlinked or unparsable config as a failed unit and changes
  nothing. The services start regardless.

Change pins in Nix, everything else in Hermes. Pin changes restart the
dashboard and gateway on activation; a seed change does nothing to an
existing config. Running sessions see config changes at their next read.
Slack adapter settings and tokens apply on a gateway restart.

Nix owns the service: do not use `hermes gateway install`, `hermes gateway start`,
or `hermes update`. Change the existing flake input and use the guarded NixOS
build/test flow for upgrades. The package still reports itself as an external
(Nix) install, so Hermes's own updater stands down. A Nix rollback does not roll
back Hermes-owned config or state; back them up privately before upgrades.

## Enrollment (human-operated)

First build and test the NixOS configuration using the root instructions. A
successful `nh os test . --no-nom` installs the user, directories, config and
unit temporarily. It does not make the new system the boot default. No `switch`
is authorized as part of this pilot setup.

Do not paste secrets, login codes, or OAuth callback URLs into agent chat.

### 1. Authorize the work OpenAI account

Run as Jordan with the Nix-installed `hermes-service` launcher, explicitly
targeting the service profile. On `endeavour`, Home Manager aliases interactive
`hermes` to `hermes-service`, so CLI chats use the dashboard profile's stored history,
settings, credentials, skills, and memory—not guaranteed simultaneous ownership. New shells pick up this alias after
activation. Existing sessions are not moved. Use `command hermes` to bypass the
alias and access the old `~/.hermes` home when `HERMES_HOME` is unset; scripts
should use `hermes-service` explicitly when they need the shared home:

```bash
hermes-service auth add openai-codex --type oauth --label work --no-browser
```

Open the URL printed by Hermes yourself, enter its device code, and select the
**work** account/workspace. Workspace policy may require an administrator to
allow Codex/device login. If denied, stop and resolve the policy; do not import
another app's tokens or substitute a personal account.

This creates a fresh grant in Hermes's own auth store; it does not copy
`~/.codex/auth.json`. It is subscription-backed authentication, not an API key.
Availability, quotas, and permitted use are still governed by the work plan and
OpenAI policy; Slack app registration does not change those terms.

The default is `gpt-6.1-sol`, verified in the live Codex catalog for the enrolled
FloSports account. To change it, update `services.hermes.model` in
`hosts/endeavour/configuration.nix` and rebuild/test rather than editing the
generated config or enabling an API-key fallback. Existing chats with an
explicit model override may retain their selection.

`display.busy_input_mode = "steer"` applies to CLI/Desktop/Conduit chat and the
messaging gateway: follow-ups guide the current run rather than interrupt it.
Clients that explicitly send an interrupt/redirect RPC can still override that
behavior; Stop remains available. Hermes may queue input during protected phases
such as context compression.

### 2. Configure the JordanBot Slack app

JordanBot already exists in the work workspace. In **api.slack.com/apps →
JordanBot**, it needs the full Hermes scope and event set; the reference is
`docs/runbooks/jordanbot-slack-manifest.json` (Hermes's own generated manifest,
plus `reactions:write`, minus its 50 global slash commands; use `!help`, `!new`).

- **Bot token scopes:** `app_mentions:read`, `assistant:write`,
  `channels:history`, `channels:read`, `chat:write`, `commands`,
  `files:read`, `files:write`, `groups:history`, `groups:read`,
  `im:history`, `im:read`, `im:write`, `mpim:history`, `mpim:read`,
  `reactions:read`, `reactions:write`, `users:read`.
- **Bot events:** `app_context_changed`, `app_home_opened`, `app_mention`,
  `message.channels`, `message.groups`, `message.im`, `message.mpim`,
  `reaction_added`. Leave `reaction_removed` off: removing a `:jordanbot:`
  reaction would start a second turn.
- **Socket Mode** on, with an app-level token (`xapp-`) scoped
  `connections:write`. **Interactivity** on. **App Home → Messages tab** on.
- **Agents → Agent experience** on, for the working-status line and streaming.
  Leave **Slack MCP Server** off.

Reinstall after any scope or event change. Invite JordanBot to each channel
where you want it (`/invite @JordanBot`); it sees nothing elsewhere.

### 3. Slack tokens

The tokens live in the Hermes-owned `.env`. Set them in **Desktop → Messaging
→ Slack**, or in your own terminal with hidden entry (not under `set -x`):

```bash
(
  set +x; set -eu; umask 077
  read -rsp 'Slack bot token (xoxb-): ' bot; printf '\n'
  read -rsp 'Slack app token (xapp-): ' app; printf '\n'
  [[ "$bot" =~ ^xoxb-[A-Za-z0-9-]+$ && "$app" =~ ^xapp-[A-Za-z0-9-]+$ ]] || exit 1
  f=~/.local/share/hermes-service/.env; touch "$f"
  { grep -v -E '^SLACK_(BOT|APP)_TOKEN=' "$f" || true
    printf 'SLACK_BOT_TOKEN=%s\nSLACK_APP_TOKEN=%s\n' "$bot" "$app"; } > "$f.new"
  mv "$f.new" "$f"
)
```

Never paste tokens into chat or screenshots. Test them without printing them
(this does not open a Socket Mode connection):

```bash
env_file=~/.local/share/hermes-service/.env
sed -n 's/^SLACK_BOT_TOKEN="\{0,1\}\(xoxb-[A-Za-z0-9-]*\)"\{0,1\}$/Authorization: Bearer \1/p' "$env_file" |
  curl -sS -H @- https://slack.com/api/auth.test | jq '{ok, error, team, user, user_id, bot_id}'
sed -n 's/^SLACK_APP_TOKEN="\{0,1\}\(xapp-[A-Za-z0-9-]*\)"\{0,1\}$/Authorization: Bearer \1/p' "$env_file" |
  curl -sS -X POST -H @- https://slack.com/api/apps.connections.open | jq '{ok, error}'
# Expect ok: true twice. Print only these fields: the full reply holds a socket ticket.
```

After a token rotation (or a reinstall that changes the bot token), update
`.env` and restart the gateway.

### 4. Enable JordanBot

```bash
sudo touch /var/lib/hermes-secrets/jordanbot-enabled
systemctl start hermes-gateway        # no sudo: polkit allows the owner
journalctl -u hermes-gateway --since '5 minutes ago'
```

Expect `Authenticated as @jordanbot` and `Socket Mode connected`. To stop and
prevent reconnection on restart or reboot:

```bash
sudo rm /var/lib/hermes-secrets/jordanbot-enabled
systemctl stop hermes-gateway
```

Dashboard restarts briefly disconnect browser/Desktop/Conduit clients. Ask for
approval before restarting a live service. Run approved NixOS test activations
from a separate transient systemd job so stopping Hermes cannot kill the
activation command before it restarts the service.

Leave Grokbot's existing listeners alone until a later explicit cutover.

## Slack: JordanBot

JordanBot is one Slack app, one Socket Mode connection (held by
`hermes-gateway`) and one Hermes profile (`default`): the same agent, memory,
skills and tools as the dashboard and `hermes-service`. Seeded behaviour, all
editable in Desktop:

| Where | Who may trigger | How |
| --- | --- | --- |
| DM with JordanBot | Jordan (`UQ69UGHKM`) | any message |
| Any channel it is in | Jordan | `@JordanBot` starts a thread; replies in that thread need no tag |
| Any message where it is | Jordan | react `:jordanbot:` to have it handle that message in its thread |
| Other people, other bots | nobody | ignored; no pairing offer |

It puts :eyes: on a message while working, then a check mark (or a cross). Replies
use Slack rich text. Cron results and notices go to the home channel, Jordan's
DM with JordanBot. Background "memory/skill updated" notices stay out of Slack.

**Editing it.** Change Slack behaviour, the allowlist or tokens in **Desktop**
(or the dashboard), then apply with `systemctl restart hermes-gateway` (no sudo).
Desktop's own gateway **Restart** button fails on this host (see below); a
`SOUL.md` or prompt change needs no restart, only a new conversation (a fresh
`@JordanBot` thread, or `!new`). Only one gateway may hold the Slack tokens:
do not start another with `hermes gateway run|start|install`.

**Known limitations (Hermes 0.22.5 as packaged by llm-agents):**

- Desktop's gateway Restart spawns a bare Python without Hermes's
  dependencies (`No module named 'ruamel'` in `logs/gateway-restart.log`).
- `hermes-service gateway status` reports "not running": the CLI does not
  recognise the Nix-wrapped gateway process. Use `systemctl status
  hermes-gateway` and `gateway_state.json`.
- Reaction triggers cannot be limited to additions; keep `reaction_removed`
  unsubscribed in the app instead.
- Lifecycle reaction emoji are fixed (:eyes:, :white_check_mark:, :x:).

These are upstream packaging issues; report them to llm-agents/Hermes rather
than patching the package here.

## Connect Hermes Desktop

The client is enabled for Jordan on `endeavour` and `opportunity` via
`users.jordangarrison.apps.hermes-desktop.enable`, and on the work MacBook
`H952L3DPHH` via Home Manager's `userApps.hermes-desktop.enable`. The two
additional machines are clients only; they do not host a copy of this service.
Build and activate their configurations on those machines before use, following
the normal approval rules. On Endeavour, both the client and dashboard run as Jordan, but
use separate profiles. Do not run the GUI with sudo
or point its local runtime at `/home/jordangarrison/.local/share/hermes-service`.

After build/test and certificate issuance:

1. Connect the client device to the same tailnet; its Tailscale ACL must permit
   access to Endeavour on port 443.
2. Launch **Hermes** → **Settings → Gateways → Add connection → Remote gateway**.
3. Name it **Endeavour pilot**, with URL `https://hermes.jordangarrison.dev`.
4. Use **Sign in**, not **Session token**. The username is `jordangarrison`.
   Copy the generated password on Endeavour in your own terminal (Wayland),
   without printing it:

   ```bash
   sudo sed -n 's/^HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=//p' \
     /var/lib/hermes-secrets/desktop-environment | wl-copy
   ```

   Save it in your password manager for use on other devices. Paste it into the
   sign-in form, then clear the clipboard with `wl-copy --clear`. Remove any
   clipboard-manager history entry too. Never paste credentials into agent chat.
   Desktop uses the system-browser native sign-in flow and saves its own session.
5. Click **Test**; both HTTP and WebSocket checks should pass. Make this gateway
   primary and select it in Sessions. Update any previously saved localhost
   session-token connection: that credential no longer works in remote mode.
   **Local / This device** is a separate app-managed runtime, NOT this pilot.

The same HTTPS address serves the standard browser dashboard/login; `/chat` opens
the chat page. On a phone, enable Tailscale first and open it in Safari or Chrome.
If an older tab still shows a headless-backend page, reload it or open a fresh tab.
Do not use the dashboard's Restart/Update buttons to manage the Nix service.

Use the same work OAuth enrollment from above; no second subscription login is
needed for this connection. Desktop can edit Hermes's config and `.env`;
Nix restores only the pinned settings ([Seed and pins](#seed-and-pins)).
The GUI is an admin interface (including file/terminal operations), and its
chats now have coding tools with Jordan's user permissions. Treat dashboard
access as workstation access. Do not share its dashboard login.

### Tailnet boundary and remote authentication

- Cloudflare: unproxied A record `hermes.jordangarrison.dev → 100.118.65.11`,
  TTL automatic. The name is publicly discoverable, but the address is private.
- nginx: DNS-01 ACME certificate, HTTPS redirect, WebSocket proxy to localhost.
  Only loopback and Tailscale IPv4/IPv6 sources reach the application. This ACL
  matters because Endeavour's host firewall is off: DNS alone cannot prevent
  a LAN client from supplying the same Host header.
- Hermes: `dashboard.public_url` declares the trusted hostname and activates
  its remote-auth gate even though the backend binds to loopback. Password
  login produces signed sessions; WebSockets use short-lived, single-use tickets.
  Missing provider credentials fail closed. Legacy localhost tokens are rejected.
- nginx overwrites forwarding headers; Hermes trusts only the local proxy.
  Access logging is disabled for this virtual host to avoid recording WS tickets
  and native sign-in codes in query strings. Avoid publishing error/backend logs.
- No Tailscale Serve, Funnel, Cloudflare proxy, or public tunnel is involved.
  Do not bind Hermes to `0.0.0.0` or remove the source ACL to fix connectivity.

The root-owned `desktop-environment` must contain exactly these keys (values
are generated privately, never supplied through Nix):

```text
HERMES_DASHBOARD_BASIC_AUTH_USERNAME
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD
HERMES_DASHBOARD_BASIC_AUTH_SECRET
```

Setup generates independent 32-byte random hex values for the password and
signing secret. Hermes hashes the environment password in memory; the root-only
file contains the recoverable password so the operator can save it privately.
Neither secret may be placed in the repository, Nix configuration, or CLI args.
The signing secret must persist across restarts to preserve signed sessions.

Manage the two lifecycles with systemd, not Desktop's gateway install/start/
restart controls. Stop/restart only with the operator's approval:

```bash
systemctl status hermes-serve hermes-gateway
journalctl -u hermes-serve --since '5 minutes ago'
# Backend only; does not stop Slack:
sudo systemctl restart hermes-serve
```

To revoke all dashboard sessions, replace the signing secret and password in
`desktop-environment` privately, then restart `hermes-serve` with approval.
Changing only the password does not revoke existing signed sessions. This does
not revoke or replace OpenAI OAuth. Back up credentials only to private storage.

Before model enrollment, validate the front door without printing secrets:

```bash
curl -fsS https://hermes.jordangarrison.dev/api/status |
  jq '{auth_required, auth_providers, auth_flows}'
# Expect true, ["basic"], and native_pkce among the flows.
curl -s -o /dev/null -w '%{http_code}\n' https://hermes.jordangarrison.dev/api/auth/me
# Expect 401 without login.
```

A non-tailnet/LAN source sent to nginx with this Host header must get 403.
Test real Desktop sign-in from a second tailnet device; a localhost probe alone
cannot validate the client's DNS, Tailscale membership, or ACL grants.

## Shared agent setup

Hermes consumes the existing agent sources rather than maintaining copies:

- **Personal instructions:** Endeavour reads
  `users/jordangarrison/agents/AGENTS.md` into `services.hermes.instructions`,
  rendered as `agent.system_prompt`. The pinned Hermes CLI, Desktop/TUI, and
  messaging gateway resolve this overlay. Repository instructions still load
  separately for the selected workspace. Changes to personal instructions need
  a rebuild/test; this is a Nix snapshot, not an out-of-store instruction link.
  Selecting a Hermes personality or supplying an explicit prompt override may
  supersede the overlay; the default configuration does neither.
- **Skills:** `skills.external_dirs` reads `~/.agents/skills`, the Home Manager
  fan-out already used by Pi, Codex, OMP, and OpenCode. Hermes retains its own
  writable skills directory. Same-named local skills take precedence over
  external ones; audit names before assuming parity. Store-backed external
  skills are immutable, but repository-backed links retain normal filesystem
  write permissions. Do not install duplicate copies into the Hermes profile.
- **Terminal sessions:** run `hermes-service` from the desired repository. The
  launcher sets `HERMES_HOME`, passes arguments unchanged,
  and does not change directory. It shares provider OAuth, skills, configuration,
  and session storage with the service, but runs as an interactive process. It
  does not load root-owned service secrets. Do
  not use it to start a second gateway/backend or a local Desktop runtime.
- **Herdr:** `services.hermes.herdrIntegration.enable` packages the unmodified
  `herdr-agent-state` plugin shipped by the pinned Herdr binary. Its installer
  runs only in an isolated build home; Nix installs/enables the result alongside
  Conduit. Do not run `herdr integration install hermes` against the
  service profile: the installer rewrites `config.yaml` and plugin links. Launch
  `hermes-service` in a Herdr shell pane. The plugin reports session identity
  only when Herdr pane context is present. Other Hermes profiles are untouched.

- **MCP:** Endeavour maps the host-gated `programs.mcp.servers` inventory
  (`users/jordangarrison/home.nix`) into `services.hermes.mcpServers`, rendered
  as the service profile's `mcp_servers`. Remote servers use `auth = "oauth"`.
  Add or change servers there, not in Hermes. Enroll each OAuth server once,
  in your own terminal: `hermes-service mcp login <name>`. Tokens stay in
  `/home/jordangarrison/.local/share/hermes-service/mcp-tokens/`, never in Nix.
  Do not copy other agents' tokens.

### Named profiles

There is one bot today: the `default` profile. `services.hermes.profiles.<name>`
can pin settings into a named profile created in Hermes later
(`hermes-service profile create <name>`): `mcpServers` (names from
`services.hermes.mcpServers`) and `shareMcpTokens` (link its `mcp-tokens` to the
service profile's, reusing those OAuth grants). Removing a declaration undoes
exactly what Nix pinned. Hermes 0.22 serves every named profile from the one
gateway, including its cron jobs; route a channel to it with Hermes's
`gateway.profile_routes`. The earlier `sre-review-bot` profile was deleted in
Hermes (its tombstone keeps it from being revived).

### Remaining parity gaps

Interactive shell environment is not automatically inherited by the services.
Keep wrappers for credentials, and add only explicitly required runtime/socket
access after checking it. Do not bulk-import `~/.env`. Privileged operations use
Jordan's existing sudo policy, not a separate agent-specific privilege grant.

### Build now, activate only with approval

```bash
nix build .#checks.x86_64-linux.hermes-module .#checks.x86_64-linux.hermes-runtime --no-link
nh os build . --no-nom
# STOP here until test activation is explicitly approved:
nh os test . --no-nom
```

Test activation can restart the backend hosting Desktop/Conduit chats. Arrange
an operator terminal before proceeding. No `nh os switch` is part of this flow.
When upgrading from the previously sandboxed service, the first activation must
run from an ordinary user terminal: the running process cannot remove its own
`NoNewPrivileges` restriction. New service processes get the updated policy.
After test activation, verify a new chat's shared instructions/skills, launch
`hermes-service` in a disposable repository, and verify Herdr session detection
and restoration under the same profile. Offline hook tests do not prove live
Herdr restoration. Likewise, verify Git/SSH and required credential wrappers
from the actual service context before claiming operational parity.

## Native Hermes plugins (including Conduit)

Plugin installation and enablement belong to Nix on this host, just like the
Hermes configuration. Do **not** use Conduit's **Install or Update** button,
`hermes plugins install/update/enable`, or `hermes gateway restart` on the pilot.
Those instructions assume a mutable, CLI-managed installation. Use `hermes-service` explicitly in scripts; bare `command hermes` can select
the separate personal home instead of the dashboard profile.

The current plugin is `kaishi00/hermes-conduit-notifier`, manifest name
**`conduit_push`**, version **0.70.2**, pinned by commit and hash in
`packages/hermes-conduit-notifier/default.nix`. It is loaded unchanged by the
published Hermes package, with no agent-package override or third-party patch.

### Add or update a plugin

1. Inspect its source, manifest, dependencies, hooks, external destinations,
   and compatibility with the pinned Hermes version. Native plugins execute
   trusted Python code with the service's permissions: disabling model tools
   is not a plugin security sandbox.
2. Package a pinned source under `packages/<plugin>/default.nix` using
   `fetchFromGitHub` with a full commit and hash (Conduit is the example).
   Plugin dependencies must already be available from Hermes or be packaged
   explicitly; do not `pip install` into its Nix store environment.
3. Add it to the Endeavour service by **manifest name**:

   ```nix
   services.hermes.plugins.conduit_push =
     pkgs.callPackage ../../packages/hermes-conduit-notifier { };
   ```

   The module generates `plugins.enabled` and links the read-only source under
   `/home/jordangarrison/.local/share/hermes-service/plugins/<name>`. Plugin data/pairings remain mutable in
   `/home/jordangarrison/.local/share/hermes-service`, not inside the source directory.
4. Extend the runtime tests for loading, authenticated API routes, and model
   tool selection. **Hermes auto-enables newly discovered plugin toolsets even
   with an empty platform list.** This personal instance permits Conduit tools;
   do not assume installing a plugin only adds passive notifications.
5. Run both Hermes flake checks, then `nh os build . --no-nom`. Ask before
   `nh os test . --no-nom`. Source changes trigger a backend/gateway restart;
   no manual gateway install/restart command is needed. No switch without
   separate approval.

To update Conduit, change its pinned commit/hash/version, adjust the version
assertions in the runtime tests, and repeat the checks/build/test flow. To
remove it, remove the host's plugin entry and rebuild/test. Any leftover source
symlink is inert because the plugin is no longer enabled; remove obsolete
links only after confirming they contain no user-managed files.

For **our own native plugins**, write a directory containing `plugin.yaml` and
`__init__.py` exposing `register(ctx)`, following the pinned Hermes SDK. Package
that local directory as a derivation and add it to the same Nix attribute set.
A Hermes plugin is not a pi extension or a Claude Code plugin: those APIs do not
transfer automatically. Existing `SKILL.md` workflows are a separate migration;
review their required tools, paths, credentials, and harness assumptions before
exposing them to Hermes. Running as Jordan makes user files accessible, but
does not automatically port another harness's APIs or import its configuration.

### Enable Conduit features on the phone

After the approved test activation, reconnect Conduit to
`https://hermes.jordangarrison.dev`. **Settings → Conduit plugin** should report
0.70.2 rather than missing. Chat takeover routes are available behind the same
dashboard authentication; actual takeover still needs a live compatible chat.

Installing the plugin does **not** pair notifications or share phone data.
For push notifications, opt in under **Settings → Notifications** and pair the
active pilot profile. Conduit can submit the pairing code over the existing
HTTPS connection. No public inbound listener is added.

- Notifications use the external `https://push.milim.dev` relay and Apple APNs.
  Check that end-to-end encryption is active before using work conversations.
- Use `hermes-service conduit-push status` (launcher above) to inspect pairing
  without printing credentials. `hermes-service conduit-push redact on` suppresses
  chat titles/bodies in push payloads; choice labels/routing metadata remain.
- Health, location, contacts, calendar sharing, voice engines, Pulse automation,
  and Watch jobs are not activated by this installation. Choose those separately
  in Conduit. Optional voice runtimes are not packaged.
- Pairing secrets are kept in `conduit-push.json` under the pilot home. Do not
  paste pairing codes, tokens, or that file into agent chat.
- Nix updates roll back plugin code, not mutable pairing/state. Back it up
  privately before upgrades; schema downgrades are not guaranteed safe.

## Acceptance checks

Offline checks validate module settings and the pinned Hermes config parser.
The sandboxed server smoke test checks local auth, remote password login, secure
cookies, host/origin denial, WS tickets/replay rejection, client disconnect, and
startup refusal without credentials. They do not prove live OAuth, Slack
delivery, or cross-device Desktop connectivity.

After manual enrollment:

1. DM JordanBot from Jordan's account; confirm the reply is from **JordanBot**.
   In a channel it is in, `@JordanBot` once, then reply in the thread without
   a tag; react `:jordanbot:` to another message. See [Slack](#slack-jordanbot).
2. In a disposable project directory, verify terminal execution, file read/write,
   and a harmless build/test command. Do not use real credentials as test data.
   No model-backed coding check is possible until OAuth enrollment succeeds.
3. With a consenting colleague, check that their DM gets no response or pairing
   offer. Do not widen the allowlist for this check.
4. Ask before restarting the service; then confirm another DM works and the
   prior conversation remains available. Verify reconnect after a network blip.
5. Test logout/client disconnect: both system units must remain running. Close
   Desktop and confirm another Slack DM still works. Reopen Desktop and verify
   the shared profile/session history is available. Model chat and cross-interface
   history checks require real enrollment; offline checks do not prove them.
6. Reboot survival is a later check, after an explicitly approved switch makes
   the unit part of the boot configuration. No reboot or switch during setup.

## Migration from the initial Slack-only account

The original `hermes-slack` service/user used `/var/lib/hermes-slack` and
`/var/lib/hermes-slack-secrets`. The owner-account migration stops both old
processes, snapshots the state and secrets privately under `/var/backups/hermes`,
copies state into `~/.local/share/hermes-service`, changes only the copy's
ownership, and copies root-owned secrets into `/var/lib/hermes-secrets`. Nix
then installs the new config/plugin symlinks and starts the renamed units via
`nh os test . --no-nom`. Never copy live SQLite state while its writers run.

Existing sessions, Conduit pairing and dashboard signing secrets are preserved.
The old directories are retained, not deleted, for rollback. Do not launch both
old and new profiles against the same Slack tokens. To roll back, stop both new
units, restore the old tested system and old profile; changes made after migration
will only be in the new profile. A test activation does not change the boot default.

## Later phases

Add scheduled-message testing, then a bounded Herdr coordinator, then existing
review skills. Keep the Slack allowlist and tailnet authentication in place.
Use durable event/PR-head IDs and result records before unattended review
posting. Reconcile current skills/channel instructions with the earlier bot
policy rather than copying conflicting rules into multiple profiles.

Upstream references (check the installed version before adopting options):
- <https://github.com/NousResearch/hermes-agent/blob/v0.22.2/website/docs/getting-started/nix-setup.md>
- <https://github.com/NousResearch/hermes-agent/blob/v0.22.2/website/docs/user-guide/messaging/slack.md>
- <https://github.com/NousResearch/hermes-agent/blob/v0.22.2/website/docs/user-guide/multi-connection-desktop.md>
