---
name: github-app-setup
description: GitHub App setup for an organization through the manifest flow. Use when a repo, bot, or workflow needs a new GitHub App, with its client ID and private key stored as the repo's Actions variable and secret. Needs gh, python3, and an org owner at a browser.
---

# GitHub App setup

GitHub has no API that creates an App: an org owner must click **Create** and **Install** in a browser. Everything around those two clicks goes through `scripts/gh-app-setup.py` in this skill's directory (`H` below); `H --help` and `H <command> --help` give exact syntax. The helper keeps the private key, client secret, and webhook secret out of stdout, argv, and chat. Read the credentials only through it.

Invoking the skill is the consent. The owner's **Create** click is the real gate. One stop remains, even with `--yolo`: if the target variable or secret name already exists, ask before overwriting it.

## 1. Collect the inputs

| Input | Example |
|---|---|
| Org | `acme` |
| App name (unique on all of GitHub) | `acme-release-bot` |
| Description, homepage URL | the repo URL works as the homepage |
| Permissions, least needed | `contents=write`, `pull_requests=write` |
| Repos to install on | `acme/releases` |
| Repo that gets the credentials, variable name, secret name | `acme/releases`, `RELEASE_BOT_CLIENT_ID`, `RELEASE_BOT_PRIVATE_KEY` |

Permission names are the keys of the App permissions object in GitHub's REST docs. GitHub adds `metadata=read` itself. The helper makes Apps with the webhook off; if the App needs one, the owner turns it on in the App's settings after creation. Ask for any input the request leaves open.

## 2. Preflight

```bash
H preflight --org <org> --name <name> --repo <owner/repo> --var <VAR> --secret <SECRET>
```

Done when it exits 0: the gh user is an org owner (`role: admin`), the name is free, and you know which variable and secret names already exist on the repo. If the gh user is not an owner, an owner must run this skill. A taken name needs a new name.

## 3. Expose the page to the owner's browser

Pick the first that fits and note the **base URL** and **bind** address:

1. **Owner's browser is on this machine**: bind `127.0.0.1`, base `http://127.0.0.1:<port>`.
2. **`tailscale serve` works without sudo** (the user is the Tailscale operator): bind `127.0.0.1`, then `tailscale serve --bg --https=<port> http://127.0.0.1:<port>`; base `https://<magicdns-name>:<port>`. Check `tailscale serve status` first and pick a port it does not use, so you add to the existing config and leave it otherwise unchanged.
3. **Otherwise**: bind the Tailscale IP (`tailscale ip -4`); base `http://<magicdns-name>:<port>`.

The MagicDNS name is `.Self.DNSName` in `tailscale status --json`, without the trailing dot. The helper accepts only loopback and Tailscale addresses.

## 4. Serve the manifest page

Use a private work dir, for example `~/.local/share/<app-name>-setup`. Start the server detached, with a hard time limit:

```bash
setsid nohup timeout 3h H serve --org <org> --name <name> --description <text> \
  --url <homepage> --perm contents=write --perm pull_requests=write \
  --repo <owner/repo> --base-url <base> --bind <bind> --port <port> \
  --dir <dir> >> <dir>/serve.log 2>&1 < /dev/null &
```

Create `<dir>` with mode 700 before you redirect into it. The server writes its PID to `<dir>/server.pid`; stop it with `kill "$(cat <dir>/server.pid)"`. A PID file is the only safe way to stop it: `pkill -f <pattern>` also matches, and kills, the shell running the pkill.

Send the owner the base URL and this warning, word for word:

> Open <base>/ and click Continue, then Create GitHub App. After that, GitHub sends you back to a page with a `code=` value in the address bar. Do not paste that address anywhere: for one hour, anyone with it can take the App's private key.

## 5. Wait for the credentials

Watch for `<dir>/result.json` with the harness's watch facility (pi: `until`; elsewhere a background poll), condition `test -s <dir>/result.json`. The server exits after it writes the file and prints the App's slug, ID, and client ID to `serve.log`. The callback page tells the owner to install the App with **Only select repositories**. If the 3-hour limit passes first, report that and go to "Abandon".

## 6. Verify the install

The App's own key proves which repos it can reach. Signing the token needs `openssl` (`nix shell nixpkgs#openssl -c` if it is missing):

```bash
H verify-install --org <org> --repo <owner/repo> [--repo ...] --dir <dir>
```

| Exit | Meaning | Next |
|---|---|---|
| 0 | Installed on exactly the expected repos, selection `selected`. | Continue. |
| 3 | Not installed yet. | Remind the owner, then watch this command until it exits 0. |
| 1 | Wrong selection or repos. | Send the owner the printed `settings_url` to fix it, then run again. |

If the owner chooses not to install yet, continue to step 7 and tell them to confirm the selection at `https://github.com/organizations/<org>/settings/installations` later. After step 7 the key is gone, so this check cannot run again.

## 7. Store and destroy the credentials

```bash
H store --repo <owner/repo> --var <VAR> [--app-id-var <VAR>] --secret <SECRET> --dir <dir>
```

It sets the variable with `gh variable set`, pipes the private key to `gh secret set` on stdin, confirms both names with `gh variable list` and `gh secret list`, then shreds `result.json`, `state`, and `serve.log` and removes `<dir>`. On failure it keeps `result.json` for a retry.

Then clean up. Done when all of these hold:

- `<dir>` does not exist.
- No process listens on the port (`ss -ltn`).
- If you used option 2 in step 3: `tailscale serve --https=<port> off`, and `tailscale serve status` no longer lists the port.

## Abandon

Stop the server with its PID file, `shred -u <dir>/*`, `rmdir <dir>`, and undo any `tailscale serve` entry. If GitHub already created the App, the owner deletes it in the org's **Developer settings → GitHub Apps** page.

## Report

App slug and URL, installation ID and repos, the variable and secret names set, and the cleanup checks.
