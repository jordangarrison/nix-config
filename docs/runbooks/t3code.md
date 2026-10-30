# T3 Code on endeavour

## Ownership and access

- URL: `https://t3code.jordangarrison.dev` (Tailscale required).
- DNS: unproxied A record to `100.118.65.11`, TTL 1.
- NixOS unit: `t3code.service`, starts at boot as `jordangarrison`.
- Backend: `127.0.0.1:3773`; nginx provides TLS, WebSockets and a tailnet allowlist.
- State: `/home/jordangarrison/.local/share/t3code-server/userdata`.
- Package: the same `llm-agents.t3code` release as the desktop and CLI.

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

## Sources

- `modules/nixos/t3code.nix`: service and private state directory.
- `hosts/endeavour/configuration.nix`: enablement, TLS and network policy.
- `tests/t3code-module.nix`: evaluation checks (`nix build .#checks.x86_64-linux.t3code-module`).
- [Upstream remote access](https://github.com/pingdotgg/t3code/blob/v0.1.5/docs/user/remote-access.md).
