#!/usr/bin/env python3
"""gh-app-setup: create a GitHub App from a manifest and store its credentials.

GitHub has no API that creates an App. An org owner must click "Create" in a
browser. This helper does every other part of the manifest flow:

  preflight       check the caller is an org owner, the App name is free, and
                  which variable/secret names the target repo already has
  serve           serve a one-shot page that posts the manifest to GitHub and
                  takes GitHub's callback; trades the code for the App
                  credentials and writes them to <dir>/result.json (mode 600)
  verify-install  sign in as the App (JWT from result.json) and print the
                  install's repository selection and repositories
  store           put the client ID in a repo variable and the private key in
                  a repo secret, then shred result.json and remove <dir>

Secret handling:
  - The private key, client secret, and webhook secret never go to stdout,
    argv, or any file except result.json. `store` pipes the key to
    `gh secret set` on stdin, and verify-install hands it to openssl
    through a pipe.
  - The callback `code` is as good as the private key for one hour. Only the
    owner's browser should see it.
  - `serve` binds loopback or a Tailscale address only.

Exit codes: 0 ok, 1 failed or mismatch, 2 usage, 3 not yet (no result, no
install).
"""

import argparse
import base64
import html
import ipaddress
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

API = "https://api.github.com"
EXIT_PENDING = 3


def die(msg, code=1):
    print(f"gh-app-setup: {msg}", file=sys.stderr)
    sys.exit(code)


def note(msg):
    print(f"gh-app-setup: {msg}", file=sys.stderr)


def gh(*args, input=None, check=True):
    """Run gh; return (returncode, stdout)."""
    p = subprocess.run(
        ["gh", *args], input=input, capture_output=True, text=True
    )
    if check and p.returncode != 0:
        die(f"gh {' '.join(args[:2])} failed: {p.stderr.strip()}")
    return p.returncode, p.stdout


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def write_private(path, data):
    """Create path with mode 600; fail if it already exists."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(data)


def shred(path):
    if os.path.exists(path):
        subprocess.run(["shred", "-u", path], check=True)


# ---------------------------------------------------------------- preflight


def cmd_preflight(a):
    ok = True
    _, login = gh("api", "user", "--jq", ".login")
    login = login.strip()
    rc, out = gh(
        "api", f"orgs/{a.org}/memberships/{login}", "--jq", ".role", check=False
    )
    role = out.strip() if rc == 0 else "none"
    print(f"org role: {login} is '{role}' in {a.org}")
    if role != "admin":
        ok = False
        note("only an org owner (role admin) can create and install the App")

    slug = slugify(a.name)
    rc, _ = gh("api", f"apps/{slug}", check=False)
    if rc == 0:
        ok = False
        print(f"app name: '{a.name}' (slug {slug}) is TAKEN")
    else:
        print(f"app name: '{a.name}' (slug {slug}) looks free")

    for kind in ("variable", "secret"):
        rc, out = gh(kind, "list", "--repo", a.repo, "--json", "name", check=False)
        if rc != 0:
            ok = False
            print(f"repo {kind}s: cannot list on {a.repo} (no access?)")
            continue
        names = sorted(x["name"] for x in json.loads(out or "[]"))
        print(f"repo {kind}s on {a.repo}: {', '.join(names) or '(none)'}")
        want = a.var if kind == "variable" else a.secret
        if want and want in names:
            print(f"  WARNING: {want} exists; store would overwrite it")
    sys.exit(0 if ok else 1)


# -------------------------------------------------------------------- serve

PAGE = """<!doctype html><meta charset=utf-8><title>Create {name}</title>
<body style="font-family:sans-serif;max-width:46em;margin:2em auto">
<h1>Create the GitHub App "{name}"</h1>
<p>This sends the manifest below to GitHub for the <b>{org}</b> organization.
GitHub shows the App before it creates it. Click <b>Create GitHub App</b>
there.</p>
<form method=post action="{action}">
<input type=hidden name=manifest value="{manifest_attr}">
<button type=submit style="font-size:1.2em">Continue to GitHub</button>
</form>
<h2>Manifest</h2><pre>{manifest_pre}</pre>
</body>"""

DONE = """<!doctype html><meta charset=utf-8><title>{slug} created</title>
<body style="font-family:sans-serif;max-width:46em;margin:2em auto">
<h1>App "{slug}" created</h1>
<p>The credentials are saved on the server. This page holds no secrets.</p>
<p><a href="https://github.com/apps/{slug}/installations/new"
style="font-size:1.3em">Install it now</a></p>
<p>Pick the <b>{org}</b> account, choose <b>Only select repositories</b>, and
select only: <b>{repos}</b>.</p>
</body>"""


def check_bind(host):
    if host == "localhost":
        return
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        die(f"--bind must be an IP address, not '{host}'", 2)
    tailnet4 = ipaddress.ip_network("100.64.0.0/10")
    tailnet6 = ipaddress.ip_network("fd7a:115c:a1e0::/48")
    if not (ip.is_loopback or ip in tailnet4 or ip in tailnet6):
        die(f"--bind {host}: use loopback or a Tailscale address only", 2)


def cmd_serve(a):
    check_bind(a.bind)
    os.makedirs(a.dir, mode=0o700, exist_ok=True)
    os.chmod(a.dir, 0o700)
    result_path = os.path.join(a.dir, "result.json")
    pid_path = os.path.join(a.dir, "server.pid")
    if os.path.exists(result_path):
        die(f"{result_path} exists; store or shred it first")

    state = secrets.token_urlsafe(32)
    state_path = os.path.join(a.dir, "state")
    if os.path.exists(state_path):
        shred(state_path)
    write_private(state_path, state)

    base = a.base_url.rstrip("/")
    perms = {}
    for p in a.perm:
        k, sep, v = p.partition("=")
        if not sep or v not in ("read", "write", "admin"):
            die(f"--perm '{p}': want <permission>=read|write|admin", 2)
        perms[k] = v
    manifest = {
        "name": a.name,
        "url": a.url,
        "description": a.description,
        "redirect_url": f"{base}/callback",
        "public": False,
        "default_permissions": perms,
        "default_events": [],
    }
    manifest_json = json.dumps(manifest, indent=2)
    action = (
        f"https://github.com/organizations/{urllib.parse.quote(a.org)}"
        f"/settings/apps/new?state={urllib.parse.quote(state)}"
    )
    page = PAGE.format(
        name=html.escape(a.name),
        org=html.escape(a.org),
        action=html.escape(action),
        manifest_attr=html.escape(json.dumps(manifest)),
        manifest_pre=html.escape(manifest_json),
    )

    class Handler(BaseHTTPRequestHandler):
        done = False

        def log_message(self, fmt, *args):
            # The request line holds the one-time code; log path only.
            note(f"{self.command} {urllib.parse.urlsplit(self.path).path}")

        def send(self, status, body):
            data = body.encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            u = urllib.parse.urlsplit(self.path)
            if u.path == "/":
                return self.send(200, page)
            if u.path != "/callback":
                return self.send(404, "not found")
            q = urllib.parse.parse_qs(u.query)
            if not secrets.compare_digest(q.get("state", [""])[0], state):
                return self.send(403, "state mismatch")
            code = q.get("code", [""])[0]
            if not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", code):
                return self.send(400, "bad code")
            req = urllib.request.Request(
                f"{API}/app-manifests/{code}/conversions",
                method="POST",
                headers={"Accept": "application/vnd.github+json"},
            )
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    body = r.read().decode()
            except urllib.error.HTTPError as e:
                note(f"conversion failed: HTTP {e.code}")
                return self.send(502, f"GitHub conversion failed: HTTP {e.code}")
            app = json.loads(body)
            write_private(result_path, body)
            print(
                json.dumps(
                    {
                        "slug": app["slug"],
                        "id": app["id"],
                        "client_id": app["client_id"],
                        "html_url": app["html_url"],
                    }
                ),
                flush=True,
            )
            self.send(
                200,
                DONE.format(
                    slug=html.escape(app["slug"]),
                    org=html.escape(a.org),
                    repos=html.escape(", ".join(a.repo)),
                ),
            )
            Handler.done = True

    # `timeout` and `kill` send SIGTERM; exit through the finally block below.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    srv = HTTPServer((a.bind, a.port), Handler)
    with open(pid_path, "w") as f:
        f.write(str(os.getpid()))
    note(f"serving {base}/ (bound to {a.bind}:{a.port}, pid {os.getpid()})")
    try:
        while not Handler.done:
            srv.handle_request()
    finally:
        srv.server_close()
        shred(state_path)
        if os.path.exists(pid_path):
            os.unlink(pid_path)
    note(f"wrote {result_path}; server stopped")


# ----------------------------------------------------------- verify-install


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def app_jwt(app_id, pem):
    openssl = shutil.which("openssl")
    if not openssl:
        die("openssl not on PATH; run under: nix shell nixpkgs#openssl -c ...")
    now = int(time.time())
    head = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    body = b64url(
        json.dumps({"iat": now - 60, "exp": now + 540, "iss": str(app_id)}).encode()
    )
    signing_input = f"{head}.{body}".encode()
    r, w = os.pipe()
    os.write(w, pem.encode())
    os.close(w)
    try:
        p = subprocess.run(
            [openssl, "dgst", "-sha256", "-sign", f"/dev/fd/{r}"],
            input=signing_input,
            capture_output=True,
            pass_fds=(r,),
        )
    finally:
        os.close(r)
    if p.returncode != 0:
        die("openssl could not sign the JWT")
    return f"{head}.{body}.{b64url(p.stdout)}"


def api(method, path, token, scheme="Bearer"):
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"{scheme} {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    return json.loads(data) if data else None


def load_result(d):
    path = os.path.join(d, "result.json")
    if not os.path.exists(path):
        die(f"{path} does not exist yet", EXIT_PENDING)
    with open(path) as f:
        return json.load(f)


def cmd_verify_install(a):
    app = load_result(a.dir)
    jwt = app_jwt(app["id"], app["pem"])
    installs = api("GET", "/app/installations", jwt)
    inst = next(
        (i for i in installs if i["account"]["login"].lower() == a.org.lower()),
        None,
    )
    if not inst:
        print(f"not installed on {a.org} yet")
        sys.exit(EXIT_PENDING)
    tok = api("POST", f"/app/installations/{inst['id']}/access_tokens", jwt)["token"]
    try:
        repos = api("GET", "/installation/repositories?per_page=100", tok)
    finally:
        api("DELETE", "/installation/token", tok)
    names = sorted(r["full_name"] for r in repos["repositories"])
    want = sorted(a.repo)
    print(
        json.dumps(
            {
                "installation_id": inst["id"],
                "repository_selection": inst["repository_selection"],
                "repositories": names,
                "settings_url": f"https://github.com/organizations/{a.org}"
                f"/settings/installations/{inst['id']}",
            },
            indent=2,
        )
    )
    if inst["repository_selection"] != "selected" or [
        n.lower() for n in names
    ] != [n.lower() for n in want]:
        note(f"MISMATCH: want selected repositories {want}")
        sys.exit(1)


# -------------------------------------------------------------------- store


def cmd_store(a):
    app = load_result(a.dir)
    gh("variable", "set", a.var, "--repo", a.repo, "--body", app["client_id"])
    if a.app_id_var:
        gh("variable", "set", a.app_id_var, "--repo", a.repo, "--body", str(app["id"]))
    gh("secret", "set", a.secret, "--repo", a.repo, input=app["pem"])
    del app

    _, out = gh("variable", "list", "--repo", a.repo, "--json", "name")
    vars_ = {x["name"] for x in json.loads(out)}
    _, out = gh("secret", "list", "--repo", a.repo, "--json", "name")
    secs = {x["name"] for x in json.loads(out)}
    missing = [n for n in (a.var, a.app_id_var) if n and n not in vars_]
    missing += [a.secret] if a.secret not in secs else []
    if missing:
        die(f"not found after set: {missing}; result.json kept for a retry")
    print(f"stored on {a.repo}: variables {a.var}"
          f"{', ' + a.app_id_var if a.app_id_var else ''}; secret {a.secret}")

    for name in ("result.json", "state", "serve.log"):
        shred(os.path.join(a.dir, name))
    leftover = os.listdir(a.dir)
    if leftover:
        die(f"{a.dir} still holds {leftover}; remove by hand after checking")
    os.rmdir(a.dir)
    print(f"shredded credentials and removed {a.dir}")


# --------------------------------------------------------------------- main


def main():
    p = argparse.ArgumentParser(
        prog="gh-app-setup.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("preflight")
    s.add_argument("--org", required=True)
    s.add_argument("--name", required=True, help="App name")
    s.add_argument("--repo", required=True, help="owner/name that gets the credentials")
    s.add_argument("--var", help="variable name for the client ID")
    s.add_argument("--secret", help="secret name for the private key")
    s.set_defaults(fn=cmd_preflight)

    s = sub.add_parser("serve")
    s.add_argument("--org", required=True)
    s.add_argument("--name", required=True)
    s.add_argument("--description", required=True)
    s.add_argument("--url", required=True, help="App homepage, e.g. the repo URL")
    s.add_argument(
        "--perm", action="append", default=[], metavar="NAME=LEVEL",
        help="repeat, e.g. --perm contents=write; GitHub adds metadata=read",
    )
    s.add_argument(
        "--repo", action="append", required=True,
        help="owner/name to install on (shown on the done page); repeat",
    )
    s.add_argument("--base-url", required=True, help="URL the owner's browser opens")
    s.add_argument("--bind", default="127.0.0.1")
    s.add_argument("--port", type=int, default=8765)
    s.add_argument("--dir", required=True, help="private work dir (made mode 700)")
    s.set_defaults(fn=cmd_serve)

    s = sub.add_parser("verify-install")
    s.add_argument("--org", required=True)
    s.add_argument("--repo", action="append", required=True, help="expected; repeat")
    s.add_argument("--dir", required=True)
    s.set_defaults(fn=cmd_verify_install)

    s = sub.add_parser("store")
    s.add_argument("--repo", required=True)
    s.add_argument("--var", required=True, help="variable for the client ID")
    s.add_argument("--app-id-var", help="optional variable for the numeric App ID")
    s.add_argument("--secret", required=True, help="secret for the private key")
    s.add_argument("--dir", required=True)
    s.set_defaults(fn=cmd_store)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
