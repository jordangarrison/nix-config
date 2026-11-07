// Exercise the exact upstream bundle installed by Home Manager, without a live
// Pi session, user transcript, token, or herdr-core daemon.
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const agentDir = mkdtempSync(join(tmpdir(), "ovis-pi-"));
process.env.PI_CODING_AGENT_DIR = agentDir;
const socketPath = join(agentDir, "herdr-web-ui-ask", `${process.pid}.sock`);
const handlers = new Map();
const events = new EventEmitter();
let sessionFile = "/fixture/first.jsonl";
let commands = [{ name: "fixture", source: "extension", description: "Fixture" }];
const pi = {
  events: {
    on(name, handler) {
      events.on(name, handler);
      return () => events.off(name, handler);
    },
    emit: (name, data) => events.emit(name, data),
  },
  getCommands: () => commands,
  on: (name, handler) => handlers.set(name, handler),
};
const get = (path) => new Promise((resolve, reject) => {
  const req = request({ socketPath, path, method: "GET" }, (response) => {
    let body = "";
    response.setEncoding("utf8");
    response.on("data", (chunk) => { body += chunk; });
    response.on("end", () => {
      try { resolve({ status: response.statusCode, body: JSON.parse(body) }); }
      catch (error) { reject(error); }
    });
  });
  req.setTimeout(3000, () => req.destroy(new Error("Bridge request timed out")));
  req.on("error", reject);
  req.end();
});

try {
  const { default: extension } = await import(pathToFileURL(process.argv[2]));
  extension(pi);
  assert.ok(handlers.has("session_start"));
  assert.ok(handlers.has("session_shutdown"));
  await handlers.get("session_start")({}, { hasUI: false });
  assert.equal(existsSync(socketPath), false, "Headless sessions must not serve a bridge");
  await handlers.get("session_start")({}, {
    hasUI: true,
    sessionManager: { getSessionFile: () => sessionFile, getBranch: () => [] },
  });
  assert.equal(statSync(join(agentDir, "herdr-web-ui-ask")).mode & 0o777, 0o700);
  assert.equal(statSync(socketPath).mode & 0o777, 0o600);
  const state = await get("/v1/state");
  assert.equal(state.status, 200);
  assert.equal(state.body.pid, process.pid);
  assert.equal(state.body.sessionFile, sessionFile);
  assert.deepEqual(state.body.flows, []);
  assert.deepEqual(state.body.openCalls, []);
  sessionFile = "/fixture/resumed.jsonl";
  assert.equal((await get("/v1/state")).body.sessionFile, sessionFile,
    "Session changes must report the current file, not a cached path");
  assert.equal((await get("/v1/commands")).body.commands[0].name, "fixture");
  commands = [{ name: "reloaded", source: "extension" }];
  assert.equal((await get("/v1/commands")).body.commands[0].name, "reloaded");
  assert.equal((await get("/not-an-endpoint")).status, 404);
  await handlers.get("session_shutdown")();
  assert.equal(existsSync(socketPath), false, "Shutdown must remove its socket");
  console.log("Ovis upstream Pi integration: lifecycle, session discovery, commands, and socket permissions passed");
} finally {
  await handlers.get("session_shutdown")?.();
  rmSync(agentDir, { recursive: true, force: true });
}
