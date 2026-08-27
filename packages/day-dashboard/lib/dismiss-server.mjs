#!/usr/bin/env bun
// dismiss-server.mjs — tiny localhost handler for the dashboard's ✕ dismiss
// links. It records a dismissed item key, re-renders the page instantly from
// the last run's persisted inputs (so the item disappears on click, not an
// hour later), and redirects back to the dashboard.
//
// It is reached only through the private nginx vhost (same tailnet/LAN guard),
// binds to 127.0.0.1, and does nothing but read/write JSON under the state dir
// and re-run the deterministic renderer — no shell, no user input executed.
//
// Env:
//   DAY_DASHBOARD_STATE_DIR    base state dir (default /var/lib/day-dashboard)
//   DAY_DASHBOARD_DISMISS_PORT listen port (default 8846)
//   DAY_DASHBOARD_LIBDIR       dir holding render.mjs + headline.ttf

import { createServer } from "node:http";
import { readFileSync, writeFileSync, renameSync, chmodSync, mkdirSync, rmdirSync, statSync } from "node:fs";
import { renderHtml } from "./render.mjs";

const STATE = process.env.DAY_DASHBOARD_STATE_DIR || "/var/lib/day-dashboard";
const PORT = Number(process.env.DAY_DASHBOARD_DISMISS_PORT || 8846);
const LIBDIR = process.env.DAY_DASHBOARD_LIBDIR || new URL(".", import.meta.url).pathname;
const DISMISSED = `${STATE}/dismissed.json`;
const LOCK = `${STATE}/.publish.lock`;
const PRUNE_MS = 30 * 24 * 60 * 60 * 1000;
const KEY_RE = /^[a-f0-9]{8,64}$/;
const MAX_BODY = 4096;

// Cross-process mutex (the generator's publish uses the same mkdir lock) so a
// dismiss re-render and an hourly publish can't clobber each other's
// index.html. Best-effort: steals a stale lock, gives up after ~3s.
function withLock(fn) {
  const deadline = Date.now() + 3000;
  let held = false;
  for (;;) {
    try {
      mkdirSync(LOCK);
      held = true;
      break;
    } catch (e) {
      if (e.code !== "EEXIST") break;
      try {
        if (Date.now() - statSync(LOCK).mtimeMs > 15000) {
          rmdirSync(LOCK);
          continue;
        }
      } catch {
        /* lock vanished */
      }
      if (Date.now() > deadline) break;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 40);
    }
  }
  try {
    fn();
  } finally {
    if (held) {
      try {
        rmdirSync(LOCK);
      } catch {
        /* already gone */
      }
    }
  }
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => {
      data += c;
      if (data.length > MAX_BODY) req.destroy();
    });
    req.on("end", () => resolve(data));
    req.on("error", () => resolve(""));
  });
}

// CSRF: a state change must originate from our own page. A browser form POST
// always sends Origin; a cross-site attacker's Origin/Referer host won't match
// ours (the forwarded Host). Non-browser clients (curl on the tailnet) send
// neither and are not a CSRF vector, so absence is allowed.
function sameOrigin(req) {
  const host = req.headers.host;
  const check = (u) => {
    try {
      return new URL(u).host === host;
    } catch {
      return false;
    }
  };
  if (req.headers.origin) return check(req.headers.origin);
  if (req.headers.referer) return check(req.headers.referer);
  return true;
}

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return fallback;
  }
}

function writeAtomic(path, text, mode) {
  const tmp = `${path}.tmp.${process.pid}`;
  writeFileSync(tmp, text);
  if (mode !== undefined) chmodSync(tmp, mode);
  renameSync(tmp, path);
}

function loadFont() {
  try {
    const buf = readFileSync(`${LIBDIR}/headline.ttf`);
    if (buf.length > 0 && buf.length < 400_000) return `data:font/ttf;base64,${buf.toString("base64")}`;
  } catch {
    /* Georgia fallback */
  }
  return null;
}

// Re-render index.html from the last full run's persisted inputs + current
// dismissed set. Fast (~ms) and never touches the network or the model.
function rerender(dismissed) {
  const context = readJson(`${STATE}/last-context.json`, { sources: [] });
  const briefing = readJson(`${STATE}/last-briefing.json`, null);
  const meta = readJson(`${STATE}/last-meta.json`, {});
  const html = renderHtml({ context, briefing, meta, fontDataUri: loadFont(), dismissed });
  if (html.includes("</html>") && html.length > 400) {
    writeAtomic(`${STATE}/www/index.html`, html);
  }
}

function prune(dismissed) {
  const now = Date.now();
  for (const [k, v] of Object.entries(dismissed)) {
    if (!v || now - new Date(v.dismissedAt || 0).getTime() > PRUNE_MS) delete dismissed[k];
  }
  return dismissed;
}

const server = createServer(async (req, res) => {
  let url;
  try {
    url = new URL(req.url, "http://localhost");
  } catch {
    res.writeHead(400).end("bad request");
    return;
  }

  if (url.pathname === "/dismiss" || url.pathname === "/undismiss") {
    if (req.method !== "POST") {
      res.writeHead(405, { Allow: "POST" }).end("use POST");
      return;
    }
    if (!sameOrigin(req)) {
      res.writeHead(403).end("bad origin");
      return;
    }
    const body = await readBody(req);
    const key = new URLSearchParams(body).get("k") || url.searchParams.get("k") || "";
    if (!KEY_RE.test(key)) {
      res.writeHead(400).end("bad key");
      return;
    }
    try {
      withLock(() => {
        const dismissed = prune(readJson(DISMISSED, {}));
        if (url.pathname === "/dismiss") dismissed[key] = { dismissedAt: new Date().toISOString() };
        else delete dismissed[key];
        // 0600: dismissed.json can encode which items (Slack/email/etc.) exist.
        writeAtomic(DISMISSED, `${JSON.stringify(dismissed)}\n`, 0o600);
        rerender(dismissed);
      });
    } catch (e) {
      res.writeHead(500).end(`error: ${e.message}`);
      return;
    }
    res.writeHead(303, { Location: "/", "Cache-Control": "no-store" }).end();
    return;
  }

  if (url.pathname === "/dismissed" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(readJson(DISMISSED, {})));
    return;
  }

  res.writeHead(404).end("not found");
});

server.listen(PORT, "127.0.0.1", () => {
  process.stderr.write(`[day-dashboard-dismiss] listening on 127.0.0.1:${PORT}\n`);
});
