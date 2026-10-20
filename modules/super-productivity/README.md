# Super Productivity

Self-hosted Super Productivity with WebDAV sync, reachable only on the tailnet.

| File | Option | Platforms | What it does |
| --- | --- | --- | --- |
| `server.nix` | `services.super-productivity` | NixOS | Web app + WebDAV sync on `superproductivity.jordangarrison.dev` |
| `app.nix` | `programs.super-productivity` | NixOS, nix-darwin | Desktop (Electron) app |

endeavour runs the server; every host gets the app. Both are enabled in
`flake.nix`.

Super Productivity has no accounts. Each app or browser profile keeps its own
data, and devices share it by syncing to the same WebDAV folder. Each login
gets its own folder, `/webdav/<user>/`, and Apache refuses every other
login's folder.

## Server setup (endeavour, once)

1. DNS: an unproxied A record `superproductivity` → `100.118.65.11`, TTL 1
   (see the Cloudflare DNS section of the root `AGENTS.md`).
2. Create the password file. `htpasswd` isn't on `PATH`, so take it from
   `apacheHttpd`:

   ```bash
   sudo install -d -m 700 /var/lib/super-productivity-secrets
   sudo "$(nix build --no-link --print-out-paths nixpkgs#apacheHttpd)/bin/htpasswd" \
     -B -c /var/lib/super-productivity-secrets/htpasswd jordangarrison
   ```

   The `super-productivity-webdav` unit is skipped until this file exists.
3. Build, test, then switch endeavour (root `AGENTS.md`).

### Add a person

1. Add the login to `services.super-productivity.webdavUsers` on endeavour.
   That creates their folder.
2. Add their password. Drop `-c`, which would overwrite the file:

   ```bash
   sudo "$(nix build --no-link --print-out-paths nixpkgs#apacheHttpd)/bin/htpasswd" \
     -B /var/lib/super-productivity-secrets/htpasswd <user>
   ```

3. Rebuild endeavour. Their devices use the client settings below with their
   own login in the URL and username.

## Client setup (each device)

Open **Settings → Sync**, turn on **Enable syncing**, choose **WebDAV** as the
**Sync provider**, and fill in:

| Field | Value |
| --- | --- |
| Base URL | `https://superproductivity.jordangarrison.dev/webdav/<user>/` |
| Username | `<user>` |
| Password | that login's htpasswd password |
| Sync Folder Path | `/` |

Press **Test Connection**, then save.

- **Linux desktop app** (`app.nix`) and the **web app**
  (`https://superproductivity.jordangarrison.dev`, installable as a PWA): the
  form opens pre-filled for the first `webdavUsers` entry. Type the password.
  Anyone else changes the URL and username to their own login.
- **macOS desktop app, Android, iOS:** fill in every field by hand. The device
  must be on the tailnet.

Sync settings are stored in the app's own database, so Nix can't set the
password. The Linux app launches with `--custom-url` pointing at the server,
which is why its form comes pre-filled (see `app.nix`).

### Second and later devices

Enable sync on a device with no data of its own (fresh install), or choose
**Keep remote** if a conflict dialog appears. **Keep local** replaces the
synced data with that device's data.

### Optional encryption

**Enable end-to-end encryption** encrypts the sync file before upload, so the
server stores only ciphertext. Every device needs the same encryption password
set *before* its next sync, and a lost password can't be recovered. Traffic is
already TLS on the tailnet, so this only protects the copy on endeavour's disk.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Test Connection: 401 | Wrong password, or the URL names another login's folder |
| Test Connection: 403 | URL is `/webdav/` without the `<user>/` folder |
| Site shows another service's certificate | This config isn't active on endeavour; build/test/switch it |
| Sync unit not running | `/var/lib/super-productivity-secrets/htpasswd` is missing |

```bash
systemctl status super-productivity-webdav
journalctl -u super-productivity-webdav -f
```
