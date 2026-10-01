# bb on NixOS

`modules/nixos/bb.nix` manages **one** system service: `bb-app start` supervises
both the server and host daemon. Endeavour enables it as `jordangarrison`.
The module is also exported as `nixosModules.bb`.

## Configuration

Package defaults use this repo's `pkgs.llm-agents` overlay. Outside this repo,
either expose that package set or explicitly set `package` and each enabled
provider's `package` from your `llm-agents` input.

```nix
services.bb = {
  enable = true;
  user = "jordangarrison"; # Must already exist in users.users.
  # group and home default to that user's NixOS account settings.
  # dataDir defaults to "${home}/.bb" and is created with mode 0700.
  providers = {
    cursor.enable = true;
    codex.enable = true;
    pi.enable = true;
    claude.enable = true;
  };
  extraPackages = with pkgs; [ nodejs ripgrep ];
  # environmentFile = "/run/secrets/bb";
};
```

Provider toggles add executable packages to PATH; they do not manage bb's
provider selection, authentication or native config. They default to disabled.
The daemon also sees the user's Nix profiles and system tools. NixOS login-shell
initialization is prevented from replacing the service PATH; user shell startup
scripts should likewise preserve the inherited PATH.

bb runs with the account's HOME, so native Git/SSH/agent configs, credentials and
skills remain accessible. It has the user's full filesystem permissions and is
**not sandboxed**. Stopping it stops child agents too. A boot-time system service
will not automatically inherit a graphical session's unlocked keyring, D-Bus
session, SSH agent or display environment. File-based credentials work normally;
interactive/session-based authentication may need additional setup.

## Appearance

Home Manager provides the Rosé Pine theme from `modules/home/bb/`: Rosé Pine
for dark mode and Rosé Pine Dawn for light mode, with terminal and code colors.
After Home Manager installs the theme files, select the palette:

```bash
bb theme set rose-pine
```

BB stores the active palette in its database and applies changes live. Light
or dark mode remains a per-client setting. The theme files use `force = true`
so Home Manager can adopt the files installed for the first live activation.

## Credentials

`environment` is only for non-secret settings: its values appear in the store.
Use a **quoted runtime path** for `environmentFile`, never a Nix path literal or
`writeText` with credentials. Provision the file separately, mode 0600; systemd
reads it as root. The module does not install a secret manager, create credentials
or copy provider secrets. Do not override HOME, PATH or update-related variables
in the environment file.

## Networking and version ownership

Defaults are `127.0.0.1:38886`, `openFirewall = false`. The reusable module adds
no nginx, DNS or Tailscale Serve configuration.

Endeavour's host configuration serves **https://bb.jordangarrison.dev** through
nginx with ACME DNS-01 certificates and WebSocket proxying to localhost. The
unproxied Cloudflare A record points at `100.118.65.11` (TTL 1). Access is limited
to loopback and Tailscale client addresses; LAN addresses are denied because
Endeavour's host firewall is already disabled. Connect to Tailscale to use this
URL. `services.bb.environment.BB_APP_URL` sets the HTTPS origin for browser
checks and generated links. This uses the existing nginx/ACME infrastructure,
not Tailscale Serve.

The pinned llm-agents bb-app 0.44.0 supports `start --bundled --data-dir
--server-port --server-bind-host`. In-app updates require `--in-app-updates`,
which is deliberately absent; `--bundled` selects the packaged code.
Host-daemon auto-update is disabled too. Do not enable updates via extraArgs,
manual launcher commands or environment files. Update the existing llm-agents
input and rebuild instead; no private bb derivation or upstream patch is used.

Upstream references:
- https://github.com/get-bb/bb/tree/main/packages/bb-app
- https://github.com/numtide/llm-agents.nix/tree/main/packages/bb-app

## Validation and operation

```bash
nix build .#checks.x86_64-linux.bb-module
nh os build . --no-nom
# Test activation can start/restart services: obtain approval first.
nh os test . --no-nom
# Only after build + test pass and explicit switch approval:
nh os switch . --no-nom

systemctl status bb --no-pager
journalctl -u bb -n 50 --no-pager
curl --fail http://127.0.0.1:38886/

# Run as the configured user, after activation:
BB_DATA_DIR="$HOME/.bb" BB_SERVER_URL=http://127.0.0.1:38886 \
  "$(nix eval --raw .#nixosConfigurations.endeavour.pkgs.llm-agents.bb-app.outPath)/bin/bb" provider list --json
```

Ask before manually starting/restarting the service. Do not run another bb-app
launcher against the service's live data directory. Journal entries or bb state
may contain sensitive data: inspect locally, do not copy them into this repo.
