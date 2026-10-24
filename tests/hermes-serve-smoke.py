"""Exercise the standard dashboard and actual Conduit/sidebar RPC shapes.

No provider inference, enrollment, live user state, or terminal takeover.
"""
import asyncio
import json
import os
from pathlib import Path
import re
import secrets
import tempfile

import httpx
from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus


async def check(mode):
    remote = mode != "local"
    public_host = "hermes.jordangarrison.dev"
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        for directory in ("cron", "sessions", "logs", "memories", "skills"):
            (home / directory).mkdir()
        config = json.loads(Path(os.environ["HERMES_TEST_CONFIG"]).read_text())
        if remote:
            config["dashboard"] = {"public_url": f"https://{public_host}"}
        else:
            config.pop("dashboard", None)
        (home / "config.yaml").write_text(json.dumps(config))
        (home / "plugins").symlink_to(os.environ["HERMES_TEST_PLUGINS"], target_is_directory=True)
        token, password = secrets.token_hex(32), secrets.token_hex(32)
        env = os.environ | {
            "HOME": tmp,
            "HERMES_HOME": tmp,
            "HERMES_MANAGED": "nixos",
            "HERMES_DASHBOARD_SESSION_TOKEN": token,
            "PYTHONUNBUFFERED": "1",
            "HERMES_DISABLE_LAZY_INSTALLS": "1",
            "HERMES_MANAGED_DIR": str(home / "empty-managed"),
        }
        (home / "empty-managed").mkdir()
        for name in ("HERMES_DESKTOP", "HERMES_PARENT_PID", "SLACK_BOT_TOKEN", "SLACK_APP_TOKEN"):
            env.pop(name, None)
        if mode == "remote":
            env.update({
                "HERMES_DASHBOARD_BASIC_AUTH_USERNAME": "test-admin",
                "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD": password,
                "HERMES_DASHBOARD_BASIC_AUTH_SECRET": secrets.token_hex(32),
            })
        proc = await asyncio.create_subprocess_exec(
            os.environ["HERMES_TEST_SERVE_REMOTE" if remote else "HERMES_TEST_SERVE_LOCAL"],
            cwd=tmp, env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
        )
        try:
            if mode == "missing-credentials":
                output, _ = await asyncio.wait_for(proc.communicate(), timeout=90)
                assert proc.returncode != 0
                assert b"_READY port=" not in output
                return

            # The stock dashboard publishes its actual ephemeral listener. Do
            # not discover a canonical owner or put a custom proxy in front.
            startup = []
            async with asyncio.timeout(90):
                while True:
                    line = await proc.stdout.readline()
                    if not line:
                        output = b"".join(startup).decode(errors="replace")
                        output = output.replace(token, "[redacted]").replace(password, "[redacted]")
                        raise AssertionError(f"dashboard exited before ready: {output}")
                    startup.append(line)
                    match = re.search(rb"HERMES_DASHBOARD_READY port=(\d+)", line)
                    if match:
                        port = int(match.group(1))
                        break
            drain = asyncio.create_task(proc.stdout.read())
            if not remote:
                token_file = home / "desktop-session-token"
                token = token_file.read_text().strip()
                assert re.fullmatch(r"[0-9a-f]{64}", token)
                assert token_file.stat().st_mode & 0o777 == 0o600
            # Drain without exposing any credentials, cookies, or WS tickets.
            headers = {"Host": public_host, "X-Forwarded-Proto": "https"} if remote else {}
            with httpx.Client(base_url=f"http://127.0.0.1:{port}", headers=headers, timeout=15, trust_env=False) as client:
                def bearer(value):
                    return {"Authorization": f"Bearer {value}"}

                def websocket(query="", origin=None):
                    host = public_host if remote else "127.0.0.1"
                    return connect(f"ws://{host}:{port}/api/ws{query}", host="127.0.0.1", port=port,
                                   origin=origin, open_timeout=15)

                async def denied(query="", origin=None):
                    try:
                        async with websocket(query, origin):
                            raise AssertionError("Unauthorized WebSocket was accepted")
                    except InvalidStatus as exc:
                        assert exc.response.status_code in (401, 403)

                assert client.get("/api/health").status_code == 200
                status = client.get("/api/status").json()
                assert status["auth_required"] is remote
                assert client.get("/api/auth/me").status_code == 401
                assert client.post("/api/auth/ws-ticket").status_code == 401
                assert client.get("/api/plugins/conduit_push/capabilities").status_code == 401
                assert client.get("/api/auth/me", headers=bearer("wrong")).status_code == 401
                await denied()

                if remote:
                    assert "basic" in status["auth_providers"]
                    assert "native_pkce" in status["auth_flows"]
                    assert client.get("/api/auth/me", headers=bearer(token)).status_code == 401
                    await denied(f"?token={token}")
                    assert client.get("/api/health", headers={"Host": "evil.example"}).status_code == 400
                    body = {"provider": "basic", "username": "test-admin", "password": "wrong"}
                    assert client.post("/auth/password-login", json=body).status_code == 401
                    body["password"] = password
                    login = client.post("/auth/password-login", json=body)
                    assert login.status_code == 200
                    cookies = list(login.cookies.jar)
                    assert cookies and all(cookie.secure for cookie in cookies)
                    access = next(cookie.value for cookie in cookies if cookie.name.endswith("hermes_session_at"))
                    credential = bearer(access)
                    assert client.get("/api/auth/me", headers=credential).status_code == 200
                    ticket_response = client.post("/api/auth/ws-ticket", headers=credential)
                    assert ticket_response.status_code == 200
                    ticket = ticket_response.json()["ticket"]
                    await denied(f"?ticket={ticket}", "https://evil.example")
                    # A rejected upgrade may consume its credential before
                    # the origin guard; never reuse a ticket across attempts.
                    ticket = client.post("/api/auth/ws-ticket", headers=credential).json()["ticket"]
                    query = f"?ticket={ticket}"
                    origin = f"https://{public_host}"
                else:
                    credential = bearer(token)
                    query, origin = f"?token={token}", None

                async def rpc(ws, method, params):
                    request_id = secrets.token_hex(8)
                    await ws.send(json.dumps({"jsonrpc": "2.0", "id": request_id,
                                              "method": method, "params": params}))
                    async with asyncio.timeout(30):
                        while True:
                            reply = json.loads(await ws.recv())
                            if reply.get("id") == request_id:
                                assert "error" not in reply, reply
                                return reply["result"]

                async with websocket(query, origin) as ws:
                    # Require application readiness and an RPC reply, not
                    # only a successful HTTP WebSocket upgrade.
                    ready = json.loads(await asyncio.wait_for(ws.recv(), timeout=15))
                    assert ready["method"] == "event", ready
                    assert ready["params"]["type"] == "gateway.ready", ready
                    assert not ready["params"].get("payload", {}).get("session_authority", False), ready
                    await ws.send(json.dumps({"jsonrpc": "2.0", "id": "smoke-ping",
                                              "method": "gateway.ping", "params": {}}))
                    async with asyncio.timeout(15):
                        while True:
                            reply = json.loads(await ws.recv())
                            if reply.get("id") == "smoke-ping":
                                assert reply.get("result") == {"ok": True}, reply
                                break
                    if remote:
                        # Exact regression from the bundled web sidebar:
                        # canonical owners reject close_on_disconnect.
                        side = await rpc(ws, "session.create", {
                            "source": "tool", "close_on_disconnect": True,
                            "profile": "default",
                        })
                        assert side["session_id"]
                        # Conduit's ordinary create and fallback-history
                        # resume, not a hand-written canonical-only happy path.
                        created = await rpc(ws, "session.create", {
                            "source": "desktop", "cols": 96, "cwd": tmp,
                        })
                        sid = created["session_id"]
                        stored_sid = created["stored_session_id"]
                        resumed = await rpc(ws, "session.resume", {
                            "session_id": stored_sid, "cols": 96, "source": "desktop",
                            "inline_images": False,
                        })
                        assert resumed["session_id"] == sid
                        print(json.dumps({"conduit_and_sidebar_rpc_contracts": "passed"}))
                if remote:
                    await denied(query, origin)  # ticket is single-use
                    # A normal dashboard chat stays available on reconnect;
                    # the sidebar-only close_on_disconnect session does not.
                    ticket4 = client.post("/api/auth/ws-ticket", headers=credential).json()["ticket"]
                    async with websocket(f"?ticket={ticket4}", origin) as last:
                        assert (await rpc(last, "session.resume", {"session_id": stored_sid}))["session_id"] == sid
                assert client.get("/api/auth/me", headers=credential).status_code == 200
                capabilities = client.get("/api/plugins/conduit_push/capabilities", headers=credential)
                assert capabilities.status_code == 200
                assert capabilities.json()["version"] == "0.70.2"
                assert capabilities.json()["restart_needed"] is False
                assert not (home / "conduit-push.json").exists(), "Installation must not pair a phone"
                assert proc.returncode is None  # client disconnect did not stop service
                assert not (home / "auth.json").exists()
                assert not (home / "gateway.pid").exists(), "Dashboard must not launch a messaging gateway"
                page = client.get("/", headers=credential)
                assert page.status_code == 200 and "text/html" in page.headers["content-type"]
                assert "<html" in page.text.lower()
                assert client.get("/chat", headers=credential).status_code == 200
        finally:
            if proc.returncode is None:
                proc.terminate()
                try:
                    await asyncio.wait_for(proc.wait(), timeout=20)
                except TimeoutError:
                    proc.kill()
                    await proc.wait()
            if "drain" in locals():
                await drain


async def main():
    for mode in ("local", "remote", "missing-credentials"):
        await check(mode)
        print(json.dumps({"serve_mode": mode, "result": "passed"}))


asyncio.run(main())
