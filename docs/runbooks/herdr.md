# Herdr operations and recovery

Operational details for the Herdr configuration managed by this repository.
Agents should first follow the invariants in the root `AGENTS.md`.

## Declarative ownership

Herdr is managed by `programs.herdr` in `modules/home/herdr/`, gated by
`userApps.herdr.enable`. `~/.config/herdr/config.toml` is a read-only Nix
symlink. Change settings in `users/jordangarrison/home.nix` and rebuild rather
than editing the symlink or changing settings in the Herdr UI.

`pane_history` and `resume_agents_on_restore` are enabled. Runtime state is
unmanaged and lives in `~/.config/herdr/session.json` and
`~/.config/herdr/session-history.json`.

## Desktop app (temporary input)

Endeavour and Opportunity enable `users.jordangarrison.apps.herdr-app`;
flomac enables `userApps.herdr-app` in its Home Manager arguments. Only
`herdr-app` comes from the separate, pinned `inputs.herdr-app`, which tracks
[llm-agents.nix PR #11664](https://github.com/numtide/llm-agents.nix/pull/11664).
The regular `llm-agents` input, Herdr TUI, hooks, and session state are unchanged.
Once the regular input ships the desktop package, use it in
`modules/home/herdr-app/default.nix` and remove the temporary input.

The desktop package and personal configuration are managed together in
`modules/home/herdr-app/`, gated by `userApps.herdr-app.enable`. Nix owns:

- `~/.config/herdr-app/keys.json`: default app shortcuts plus the TUI's
  Alt+H/J/K/L pane focus, Alt+Shift+J/K space navigation (replacing pane
  swap on those two keys), and Alt+brace tab navigation.
- `~/.config/herdr-app/settings.json`: sounds disabled, Rosé Pine selected,
  and Source Code Pro as the terminal font.
- `~/.config/herdr-app/themes/rose-pine.json`: the local Rosé Pine palette.

These are read-only symlinks, like the TUI config. Change their source files
and rebuild; do not edit them through the app. Existing per-layout theme picks
override the settings theme. To select Rosé Pine for the shown layout, run
`herdr-app do app.theme --name rose-pine`.

Agent priority sorting is already the shipped agents mod's default. The TUI's
`onboarding`, `experimental.pane_history`, and `session.resume_agents_on_restore`
have no documented desktop settings equivalents and remain TUI-only.

Leave app runtime state (`shared.json`, `view.json`, `layouts/.state/`, core
session data) and app-generated files (the guide, types, shipped layouts and
mods) unmanaged. Do not copy the TUI's state into the desktop app.

Home Manager uses `backupFileExtension = "backup"` on these hosts. On first
activation it backs up existing regular files at the managed paths to
`<path>.backup`; an existing conflicting backup blocks activation. Check the
live files for newer preferences before applying, and move any conflicting
backups into a dated backup folder. Do not use `force = true`. The manual
migration backup is under `~/.config/herdr-app/backups/` on Opportunity.

Launch `herdr-app` or select Herdr in the desktop launcher after activation.
The desktop app needs the separate `herdr-core` (`hc`); this PR packages only
the GUI. The app offers to install a missing core into `~/.local/bin`, outside
Nix management. Adding the GUI does not install that core or migrate existing
TUI sessions. Do not replace or restart the existing TUI server for this app.

## Agent integrations

Session restoration requires current per-agent Herdr hooks. These hooks live in
mutable agent dotfiles and can drift after a Herdr update. The
`programs.herdr.integrations` option reinstalls the configured integrations on
every activation.

Two caveats:

- `pane_history` takes effect only when the server starts. Enabling it does not
  make an already-running server begin capturing history.
- Agent resume works only for panes that ran under a compatible current hook
  before the restart.

## Update without losing live processes

`herdr update --handoff` does not work on Nix because its downloader cannot
write into `/nix/store`.

1. Update the input:

   ```bash
   nix flake update llm-agents
   ```

2. Review `flake.lock`, then use the root `AGENTS.md` build → test → approved
   switch sequence.
3. Run:

   ```bash
   herdr-handoff
   ```

This invokes `herdr server live-handoff --import-exe` using the new store-path
binary while preserving pane processes. If the protocol changed incompatibly,
restart the server normally; history and agent-resume settings should restore
the session where compatible.

## Crash-loop recovery

Use this only when the server crashes during restore and the TUI reports an I/O
error. This historically occurred when old releases wrote corrupt persisted
scrollback (see `ogulcancelik/herdr#453`). Keep any quarantined history file as a
reproducer for an upstream report.

1. Confirm that no server is running:

   ```bash
   pgrep -af 'herdr server'
   ```

2. Back up both state files:

   ```bash
   cd ~/.config/herdr
   cp session.json session.json.backup-<tag>
   cp session-history.json session-history.json.backup-<tag>
   ```

3. Remove only stale sockets:

   ```bash
   rm -f herdr.sock herdr-client.sock
   ```

4. Quarantine scrollback while preserving the layout:

   ```bash
   mv session-history.json session-history.json.quarantine-<tag>
   ```

   `session.json` contains workspaces, tabs, and panes.
   `session-history.json` contains scrollback. Moving only the latter sacrifices
   scrollback but keeps the layout.

5. Restart detached:

   ```bash
   setsid herdr server >> herdr-server.log 2>> herdr-server.stderr.log </dev/null &
   ```

6. Verify that the process remains alive and the API responds:

   ```bash
   pgrep -af 'herdr server'
   herdr workspace list
   ```

7. Reattach with `herdr`.

Do not delete or overwrite the quarantined history until recovery is confirmed.

## Collie (phone web UI)

`modules/nixos/collie.nix` runs [Collie](https://github.com/AltanS/collie) on
endeavour. It runs as the `collie` system service with `User=jordangarrison`,
bound to `127.0.0.1:8787`, behind the nginx vhost
`https://collie.jordangarrison.dev`. That name is a tailnet-only A record to
`100.118.65.11`, and nginx admits only localhost and `100.64.0.0/10`.

Collie is remote shell access: a paired device can read every pane and type
into it as Jordan. Never route it through the Cloudflare tunnel.

- Pair a device on the host with `collie pair` (code is valid for 10 minutes),
  then enter the code under Settings → Paired devices. Add `--expires 30d` to
  limit the token's lifetime.
- `collie devices list` and `collie devices revoke <label>` take effect live.
- Manage the service with `sudo systemctl`, not `collie start`/`stop`.
  `start` writes and starts a second, user-level bridge on the same port, and
  `stop` only touches that user unit. `collie update` refuses on a Nix store
  path; update by bumping `packages/collie`.
- Settings live in `/etc/collie/config.toml` (`COLLIE_CONFIG`). Secrets, such
  as push keys from `collie push-keys`, go in `~/.config/collie/.env`; restart
  `collie.service` afterwards.
- Keep `~/.config/collie/.env` to secrets, and don't create
  `~/.config/collie/config.toml`. Both override `/etc/collie/config.toml`, so
  either could silently change the pinned `public_hosts` or `allowed_origins`.
