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
