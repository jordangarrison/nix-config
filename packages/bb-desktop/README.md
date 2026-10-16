# BB desktop

The root flake exposes `packages.x86_64-linux.bb-desktop`. This wraps the
upstream AppImage with Nix's FHS environment and installs its desktop entry
and icon. A separate flake is not needed for this single package.

Build and try it from the repository root:

```bash
nix build path:.#bb-desktop
nix run path:.#bb-desktop
```

`path:.` includes new package files before they are tracked by Git. Once they
are tracked, `.#bb-desktop` also works.

The launcher is named `bb-desktop` so it can coexist with the `bb` CLI.
The desktop app can attach to an existing compatible local BB server. If
there is no server, it starts its bundled server and host daemon. It uses
`~/.bb` by default; set `BB_DATA_DIR` and `BB_SERVER_PORT` for an isolated run.

Desktop self-installation and host daemon auto-updates are disabled by the
wrapper. Desktop version notifications remain enabled. Update `version` and
the AppImage hash in `default.nix` to update the package.

For installation through Home Manager, see
[the desktop module](../../modules/home/bb-desktop/README.md). The existing
`services.bb` server continues to use `llm-agents.bb-app`.
