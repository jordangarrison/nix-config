# Ovis on endeavour

Ovis serves the existing herdr-core terminals through
`https://ovis.jordangarrison.dev`. Connect Tailscale on the phone, then use
that address in the Ovis mobile app. The desktop web UI uses the same address.
Authenticate with the Ovis token, or pair the phone from **Settings → Phone &
devices** on an authenticated desktop.

## Ownership and safety

- `userApps.ovis.enable` installs the published `llm-agents.ovis` package
  and starts `ovis.service` in the user's systemd manager at login.
- The service uses `~/.local/bin/hc`. It does not install, update or restart
  herdr-core (ADR 007).
- The service binds to `127.0.0.1:7317`. The host's nginx virtual host
  provides HTTPS and allows only localhost and Tailscale clients.
- `~/.config/ovis/token.env` must contain a non-empty `OVIS_TOKEN`.
  This private runtime file is not Nix-managed. Missing or empty credentials
  prevent startup. Never put its contents in the repository or logs.
- Telemetry is off. Updates go through the existing `llm-agents` input.
- Ovis keeps pairing, push keys and other mutable state in `~/.config/ovis`.
  Preserve it across rebuilds. The optional Ovis relay is not needed.

## Pi conversations

Ovis 0.5.0 or later supports Pi chat through herdr-core. When Pi is enabled,
this module links the published `llm-agents.ovis.integrations.pi` file as
`~/.pi/agent/extensions/herdr-web-ui.js`. The extension and server therefore
update together through `llm-agents`; no local bundling step is needed.
Do not run Ovis's mutable integration installer over this Nix-managed link.

New Pi sessions load the extension automatically. In each existing interactive
session, run `/reload` when idle to load it without restarting the session.
The extension reports the exact live session file over a user-private Unix
socket under `~/.pi/agent/herdr-web-ui-ask/`; Ovis reads that file for chat.
It does not select a transcript by guessing from the working directory.
Headless Pi sessions do not expose this bridge.

This enables conversation discovery and extension-command discovery. The
upstream bridge's interactive form support targets `@eko24ive/pi-ask`, not
`pi-ask-user`; those are separate extensions. Continue to use the terminal
for `pi-ask-user` dialogs unless Ovis adds support for them.

## Checks

```bash
nix build --no-link .#checks.x86_64-linux.ovis-module .#checks.x86_64-linux.ovis-pi-integration
systemctl --user status ovis
curl -fsS http://127.0.0.1:7317/api/health
# An unauthenticated HTTPS API request must return 401.
curl -s -o /dev/null -w '%{http_code}\n' https://ovis.jordangarrison.dev/api/session
```

Pairing QR codes and tokens are credentials. View them only in the app; do not
capture them in command output or screenshots.
