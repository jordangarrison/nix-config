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

test("polls once a minute and ages each provider from its last successful measurement", async (t) => {
  const home = await mkdtemp(join(tmpdir(), "subscription-usage-"));
  await mkdir(join(home, ".codex"));
  await writeFile(join(home, ".codex", "auth.json"), JSON.stringify({ tokens: { access_token: "synthetic" } }));
  let state;
  let now = 1700000000000;
  const measuredAt = now;
  let failed = false;
  let fetches = 0;
  let timer;
  let pass;
  const cx = { timer: { every: (interval, run) => {
    assert.equal(timer, undefined, "only one timer is registered");
    timer = run;
    assert.equal(interval, 60000);
  } }, spawn: (run) => { pass = run(cx); }, notify() {} };
  const hooks = registerHooks({ resolve(specifier, context, next) {
    if (!Object.hasOwn(fixtures, specifier)) return next(specifier, context);
    return { url: `data:text/javascript,${encodeURIComponent(fixtures[specifier])}`, shortCircuit: true };
  } });
  t.after(async () => { hooks.deregister(); delete globalThis.usageFixture; await rm(home, { recursive: true, force: true }); });
  globalThis.usageFixture = {
    div: element, h_flex: element, v_flex: element, home: () => home,
    checking: () => false, props: () => ({}), exec: async () => ({ code: 1 }),
    shared: () => state, setShared: (_, value) => { state = value; },
  };
  t.mock.method(Date, "now", () => now);
  t.mock.method(globalThis, "fetch", async () => {
    fetches++;
    if (failed) throw new Error("Synthetic failed check");
    return Response.json({ rate_limit: { primary_window: { used_percent: 42, reset_at: (measuredAt + 60000) / 1000 } } });
  });

  const { default: SubscriptionUsage } = await import(mod);
  const view = new SubscriptionUsage();
  view.init({}, cx);
  await pass;
  const codex = () => state.providers.find((provider) => provider.id === "codex");
  const displayed = () => view.group({}, codex()).text;
  assert.equal(fetches, 1);
  assert.equal(codex().measuredAt, measuredAt);

  failed = true;
  now = measuredAt + 15 * 60000;
  timer(cx);
  await pass;
  assert.equal(fetches, 2);
  assert.equal(codex().measuredAt, measuredAt);
  assert.doesNotMatch(displayed(), /stale/);
  now++;
  assert.match(displayed(), /stale/);

  failed = false;
  timer(cx);
  await pass;
  assert.equal(codex().measuredAt, now);
  assert.doesNotMatch(displayed(), /stale/);
});
