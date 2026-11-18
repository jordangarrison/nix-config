// Run with `node --test tests/subscription-usage.mjs`. No app or provider calls.
import assert from "node:assert/strict";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { registerHooks } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const mod = new URL("../modules/home/herdr-app/mods/subscription-usage/main.js", import.meta.url);
const fixtures = {
  "gpui-kit": `export class View {}; export const { div, svg } = globalThis.usageFixture;`,
  "gpui-base": `export const { h_flex, v_flex } = globalThis.usageFixture;`,
  herdr: `export const { checking, props, agents, spaces, run, window, keys, shared, setShared,
    openOverlay, closeOverlay, home, exec, theme } = globalThis.usageFixture;`,
};

function element() {
  const children = [];
  const view = new Proxy({}, { get: (_, name) => {
    if (name === "text") return children.join(" ");
    if (name === "child") return (value) => { children.push(value.text ?? value); return view; };
    if (name === "children") return (values) => { values.forEach(view.child); return view; };
    if (name === "when") return (condition, draw) => condition ? draw(view) : view;
    return () => view;
  } });
  return view;
}

const measuredAt = 1700000000000;
const allowlist = ["openai-flo", "openai-personal", "claude-bridge"];
const card = (provider, modelProvider, used, at = measuredAt) => ({
  provider, modelProvider, account: modelProvider, measuredAt: at, state: "available",
  windows: [
    { id: "primary", label: "5h", unit: "percent", used, limit: 100, resetAt: measuredAt + 60000 },
    { id: "unknown", label: "Unknown", unit: "percent", used: null, limit: 100, resetAt: null },
  ],
});
const fixture = [
  card("openai", "openai-personal", 42),
  card("openai", "openai-flo", 60, measuredAt - 30000),
  card("openai", "excluded", 99),
  card("claude", "claude-bridge", 0),
  card("xai", "xai", 99),
];

async function setup(t, options) {
  const home = await mkdtemp(join(tmpdir(), "subscription-usage-"));
  await mkdir(join(home, ".codex"));
  await writeFile(join(home, ".codex", "auth.json"), JSON.stringify({ tokens: { access_token: "synthetic" } }));
  await mkdir(join(home, ".grok"));
  await writeFile(join(home, ".grok", "auth.json"), JSON.stringify({ access: "synthetic" }));
  let state;
  let now = measuredAt;
  let subscriptions = fixture;
  let failure;
  let timer;
  let pass;
  const commands = [];
  const fetches = [];
  const cx = { timer: { every: (interval, run) => {
    assert.equal(timer, undefined, "only one timer is registered");
    timer = run;
    assert.equal(interval, 60000);
  } }, spawn: (run) => { pass = run(cx); }, notify() {} };
  const hooks = registerHooks({ resolve(specifier, context, next) {
    if (!Object.hasOwn(fixtures, specifier)) return next(specifier, context);
    return { url: `data:text/javascript,${encodeURIComponent(`${fixtures[specifier]} // ${t.name}`)}`, shortCircuit: true };
  } });
  t.after(async () => { hooks.deregister(); delete globalThis.usageFixture; await rm(home, { recursive: true, force: true }); });
  globalThis.usageFixture = {
    div: element, h_flex: element, v_flex: element, home: () => home,
    checking: () => false, props: () => options, exec: async (...argv) => {
      commands.push(argv);
      if (failure === "command") return { code: 1, stdout: "" };
      if (failure === "json") return { code: 0, stdout: "not json" };
      return { code: 0, stdout: JSON.stringify({ result: { collection: "enabled", subscriptions } }) };
    },
    shared: () => state, setShared: (_, value) => { state = value; },
  };
  t.mock.method(Date, "now", () => now);
  t.mock.method(globalThis, "fetch", async (url) => {
    fetches.push(url);
    return Response.json({ config: { creditUsagePercent: 25, currentPeriod: { type: "USAGE_PERIOD_TYPE_WEEKLY" } } });
  });

  // Fresh module per fixture so the Herdr imports bind to this test's mocks.
  const { default: SubscriptionUsage } = await import(`${mod.href}?${encodeURIComponent(t.name)}`);
  const view = new SubscriptionUsage();
  view.init(options, cx);
  await pass;
  return {
    commands, fetches, view,
    menu: () => state.providers,
    tick: async () => { timer(cx); await pass; },
    time: (value) => { now = value; },
    reply: (rows) => { subscriptions = rows; failure = undefined; },
    fail: (mode) => { failure = mode; },
  };
}

const command = (on) => ["jagpi", ["--instance", "default", "usage", "--json"], { on, timeout: 30000 }];

test("reads Claude and distinct Codex accounts in one call on the daemon machine; only xAI fetches locally", async (t) => {
  const { commands, fetches, menu } = await setup(t, { machine: "synthetic-host", providers: allowlist });
  assert.deepEqual(commands, [command("synthetic-host")]);
  assert.deepEqual(fetches, ["https://cli-chat-proxy.grok.com/v1/billing?format=credits"]);
  assert.deepEqual(menu().map((row) => [row.label, row.windows.map((w) => w.percent), row.measuredAt]), [
    ["Claude", [0], measuredAt],
    ["Codex · openai-personal", [42], measuredAt],
    ["Codex · openai-flo", [60], measuredAt - 30000],
    ["xAI", [25], measuredAt],
  ]);
  assert.equal(menu()[0].windows[0].resetsAt, measuredAt + 60000);
  assert.equal(menu()[3].windows[0].label, "7d");
});

test("polls locally each minute and ages cached and failed reads from the original measurement", async (t) => {
  const { commands, fetches, view, menu, tick, time, reply, fail } = await setup(t, { providers: allowlist });
  const claude = () => menu()[0];
  const displayed = () => view.group({}, claude()).text;
  time(measuredAt + 15 * 60000);
  await tick();
  assert.equal(claude().measuredAt, measuredAt);
  assert.doesNotMatch(displayed(), /stale/);

  time(measuredAt + 15 * 60000 + 1);
  for (const mode of ["command", "json"]) {
    fail(mode);
    await tick();
    assert.match(displayed(), /stale/);
    assert.equal(claude().measuredAt, measuredAt);
  }
  reply([card("claude", "claude-bridge", 50, measuredAt + 15 * 60000 + 1)]);
  await tick();
  assert.doesNotMatch(displayed(), /stale/);
  assert.equal(claude().windows[0].percent, 50);
  assert.deepEqual(commands, Array.from({ length: 5 }, () => command(null)));
  assert.deepEqual(fetches, Array(5).fill("https://cli-chat-proxy.grok.com/v1/billing?format=credits"));
});

test("drops removed accounts and does not reuse old rows after the route or allowlist changes", async (t) => {
  const options = { machine: "first", providers: allowlist };
  const { menu, tick, reply, fail } = await setup(t, options);
  reply([]);
  await tick();
  assert.deepEqual(menu().map((row) => row.windows.length), [0, 0, 1]);

  reply(fixture);
  await tick();
  assert.equal(menu()[0].windows.length, 1);
  options.machine = "second";
  fail("command");
  await tick();
  assert.deepEqual(menu().map((row) => row.windows.length), [0, 0, 1]);

  reply(fixture);
  await tick();
  assert.equal(menu()[0].windows.length, 1);
  options.providers = [];
  fail("command");
  await tick();
  assert.deepEqual(menu().map((row) => row.windows.length), [0, 0, 1]);
});
