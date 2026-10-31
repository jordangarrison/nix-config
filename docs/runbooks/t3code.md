# T3 Code on endeavour

## Ownership and access

- URL: `https://t3code.jordangarrison.dev` (Tailscale required).
- DNS: unproxied A record to `100.118.65.11`, TTL 1.
- NixOS unit: `t3code.service`, starts at boot as `jordangarrison`.
- Backend: `127.0.0.1:3773`; nginx provides TLS, WebSockets and a tailnet allowlist.
- State: `/home/jordangarrison/.local/share/t3code-server/userdata`.
- Package: `llm-agents.t3code`, the same release as the NixOS desktop and CLI.
- Flo Mac client: Homebrew cask `t3-code`, not this package. It may run ahead of the server. Its app installs the Mac `t3` link. Do not also install the Nix package or the curl installer there.

This is a personal coding server. Authorized clients can run code with Jordan's
file and provider-account access. It is not a sandbox or a public shared service.
T3's pairing authentication remains enabled, in addition to the network restriction.
T3 Connect is not required or enabled by this configuration.

The desktop keeps its own state in `~/.t3`. Add the server as a remote environment
in the desktop app to use its projects and threads; do not point two servers at
the same data directory. No existing desktop state is migrated.

## First connection

After the approved NixOS build → test → switch flow, connect the client to Tailscale.
In a private terminal on endeavour, as Jordan (not root), run:

```bash
t3 auth pairing create \
  --base-dir "$HOME/.local/share/t3code-server" \
  --base-url https://t3code.jordangarrison.dev \
  --ttl 5m --label "My browser"
```

Open the generated pairing URL in that browser. Use a fresh link for each device.
The default grant is full access. Treat links and tokens as passwords: do not
paste them into agent chat, repository files or issue reports. Revoke client
sessions through **Settings → Sharing & access**. Provider logins use Jordan's
home and installed CLIs; verify their status under **Settings → Providers**.

## Operations

```bash
systemctl status t3code
journalctl -u t3code
```

`serve` prints a full-access token and QR on stdout, so the unit discards stdout
instead of storing those credentials in the system journal. Stderr still reaches
the journal; T3 keeps its own diagnostics under its private state directory.
Review diagnostics locally before sharing any of them.

Update `llm-agents` and rebuild to update T3. Do not run `t3 update`, the in-app
updater, or `t3 service install`: Nix owns the package and systemd unit. Ask before
restarting or activating a configuration; a restart interrupts agents and terminals.
Back up the server state with the service stopped for a consistent SQLite copy.

Browser automation/streamed browser tabs are separate from the web console. Their
automatic Chrome download is not validated on NixOS by this configuration. Do not
run the upstream apt-based browser setup or disable the browser sandbox as a workaround.

## jagpi ACP provider (pending upstream release)

The host opts in with `services.jagpi.acp.enable = true` in
`hosts/endeavour/jagpi.nix`. **This preparation is not deployable with the current
lock:** jagpi is pinned to `ebc5da30b262958cd74c7db91a8b638f7531f0e6`, which lacks
ACP. Merge [jagpi PR #80](https://github.com/jordangarrison/jagpi/pull/80), which adds
the Home Manager option and `jagpi-acp` launcher, before updating the production pin. The launcher must use the same `services.jagpi.package`
and `instance`, set the user runtime directory and user bus environment, and
connect to the existing `jagpi-default.service` user unit through its managed
config. No second daemon, config, or nix-config wrapper is needed.

T3 is a system service running as Jordan; jagpi is a systemd **user** service.
T3's environment does not supply `XDG_RUNTIME_DIR` or
`DBUS_SESSION_BUS_ADDRESS`. On endeavour, the launcher must reach
`/run/user/1000/jagpi/default.sock` and the user bus, rather than falling back to
`/tmp/jagpi-1000/default.sock`. This belongs in the upstream launcher, not in the
shared T3 system module. Do not change linger or service lifetime: jagpi still
starts at login and stops with the last session. T3 starting at boot does not
ensure the user runtime, user bus, or Herdr is available.

### Publish, validate, then register

1. Merge jagpi PR #80 with ACP and the launcher contract above, then run
   `nix flake update jagpi` and inspect `flake.lock`. Do not pin a local checkout
   or an unpublished revision. jagpi upgrades are Nix-managed, not npm installs
   or edits to profile symlinks.
2. Build the focused check (`nix build .#checks.x86_64-linux.t3code-module`) and
   the host (`nh os build . --no-nom`). The focused check verifies host opt-in
   and instance selection only; CI's stub does not prove launcher behavior.
   Before publication, a build may use
   `--override-input jagpi path:/home/jordangarrison/dev/jordangarrison/jagpi --no-write-lock-file`
   only once that checkout implements the contract.
3. With separate activation approval, follow build → test → switch, using
   `nh os test . --no-nom` then `nh os switch . --no-nom`. Neither activation nor
   restarting the existing daemon is authorized by this preparation. Coordinate
   any daemon restart needed to load the new ACP-capable version with its owner.
4. After approved rollout, select the **endeavour server environment**, then
   **Settings → Providers → Add provider → Show more → Local ACP command**.
   Name it `jagpi (endeavour)` and use executable
   `/etc/profiles/per-user/jordangarrison/bin/jagpi-acp`, with **no arguments**.
   The launcher supplies the instance and ACP subcommand. Do not register a Mac
   path, checkout path, `npm run`, shell expression, or temporary `result` path.
   Provider registration is mutable T3 server state, not managed by this module;
   these instructions do not register or change a provider automatically.

Use a new T3 thread with this provider. Its **jagpi configured model** comes from
jagpi/Pi on endeavour; credentials, model tiers, and plugins are not imported
from the displaying client or T3 provider settings.

### Trust and lifecycle limits

- **Trusted local owner, full access only.** T3 approval/plan modes do not gate
  jagpi tools. Do not offer this provider to untrusted clients.
- Each new ACP session gets a separate durable jagpi thread, not the owner's
  main conversation. It still inherits context and shares project/bot memory;
  this is not isolation from the default daemon's authority or state.
- Loading a saved session reconnects to that thread. Disconnecting or closing
  T3 does not stop the daemon; explicit cancellation stops the conversation's
  current run and queued inputs. Avoid simultaneous clients driving one thread.
- Client-injected MCP servers are ignored with a stderr warning. The daemon's
  MCP configuration remains in use; Herdr dispatch does not move to T3.
- A daemon disconnect fails the active request. Reconnect/load before deciding
  to resend: accepted work may still be running. T3 file rollback does not undo
  jagpi's transcript, memory, or external actions.
- Text and top-level tool streaming are supported; background activity is not
  pushed while no prompt is active. Consult upstream `docs/acp.md` for limits
  and a post-rollout streaming, cancellation, and reconnect smoke test.

## Sources

- `modules/nixos/t3code.nix`: service and private state directory.
- `hosts/endeavour/configuration.nix`: enablement, TLS and network policy.
- `tests/t3code-module.nix`: evaluation checks (`nix build .#checks.x86_64-linux.t3code-module`).
- [Upstream remote access](https://github.com/pingdotgg/t3code/blob/v0.1.5/docs/user/remote-access.md).
