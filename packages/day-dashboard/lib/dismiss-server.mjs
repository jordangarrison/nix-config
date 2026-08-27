#!/usr/bin/env node
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
import { readFileSync, writeFileSync, renameSync } from "node:fs";
import { renderHtml } from "./render.mjs";

const STATE = process.env.DAY_DASHBOARD_STATE_DIR || "/var/lib/day-dashboard";
const PORT = Number(process.env.DAY_DASHBOARD_DISMISS_PORT || 8846);
const LIBDIR = process.env.DAY_DASHBOARD_LIBDIR || new URL(".", import.meta.url).pathname;
const DISMISSED = `${STATE}/dismissed.json`;
const PRUNE_MS = 30 * 24 * 60 * 60 * 1000;
const KEY_RE = /^[a-f0-9]{8,64}$/;

function readJson(path, fallback) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return fallback;
  }
}

function writeAtomic(path, text) {
  const tmp = `${path}.tmp.${process.pid}`;
  writeFileSync(tmp, text);
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

const server = createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, "http://localhost");
  } catch {
    res.writeHead(400).end("bad request");
    return;
  }
  const key = url.searchParams.get("k") || "";
  const redirect = () => {
    res.writeHead(302, { Location: "/", "Cache-Control": "no-store" }).end();
  };

  if (url.pathname === "/dismiss" || url.pathname === "/undismiss") {
    if (!KEY_RE.test(key)) {
      res.writeHead(400).end("bad key");
      return;
    }
    const dismissed = prune(readJson(DISMISSED, {}));
    if (url.pathname === "/dismiss") dismissed[key] = { dismissedAt: new Date().toISOString() };
    else delete dismissed[key];
    try {
      writeAtomic(DISMISSED, `${JSON.stringify(dismissed)}\n`);
      rerender(dismissed);
    } catch (e) {
      res.writeHead(500).end(`error: ${e.message}`);
      return;
    }
    redirect();
    return;
  }

  if (url.pathname === "/dismissed") {
    res.writeHead(200, { "Content-Type": "application/json" }).end(JSON.stringify(readJson(DISMISSED, {})));
    return;
  }

  res.writeHead(404).end("not found");
});

server.listen(PORT, "127.0.0.1", () => {
  process.stderr.write(`[day-dashboard-dismiss] listening on 127.0.0.1:${PORT}\n`);
});
