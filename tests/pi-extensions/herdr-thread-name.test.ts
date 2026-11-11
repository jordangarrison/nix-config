// Tests for modules/home/pi/extensions/herdr-thread-name.ts.
// Run with `nix build .#checks.x86_64-linux.pi-extensions`.
import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it } from "node:test";
import herdrThreadName, { cleanName, tabToRename } from "../extensions/herdr-thread-name.ts";

type Call = { command: string; args: string[] };

// A herdr-app ls with one space; `tabs` maps tab id -> [tab name, terminals].
const ls = (tabs: Record<string, [string, string[]]>) => ({
  spaces: [
    {
      id: "sp1",
      name: "work",
      tabs: Object.entries(tabs).map(([id, [name, terminals]]) => ({
        id,
        name,
        terminals: terminals.map((terminal) => ({ terminal })),
      })),
    },
  ],
});

// Just enough of pi's ExtensionAPI: events, tools, session name and exec.
function fakePi({ name, herdrLs = ls({ tb1: ["1", ["t7"]] }) }: { name?: string; herdrLs?: unknown } = {}) {
  const handlers: Record<string, (event: any, ctx: any) => Promise<void> | void> = {};
  const calls: Call[] = [];
  const tools: any[] = [];
  let active = ["read", "bash"];
  let sessionName = name;
  const pi = {
    on: (event: string, handler: any) => {
      handlers[event] = handler;
    },
    registerTool: (tool: any) => tools.push(tool),
    getActiveTools: () => [...active],
    setActiveTools: (names: string[]) => {
      active = [...names];
    },
    getSessionName: () => sessionName,
    setSessionName: (next: string) => {
      sessionName = next;
      pending.push(handlers.session_info_changed?.({ name: next }, {}));
    },
    exec: async (command: string, args: string[]) => {
      calls.push({ command, args });
      if (command === "herdr-app" && args[0] === "ls") return { code: 0, stdout: JSON.stringify(herdrLs), stderr: "" };
      return { code: 0, stdout: "", stderr: "" };
    },
  };
  const pending: unknown[] = [];
  return {
    pi,
    calls,
    tools,
    active: () => active,
    start: (mode = "tui") => handlers.session_start?.({ reason: "startup" }, { mode }),
    rename: (next: string) => handlers.session_info_changed?.({ name: next }, {}),
    prompt: (messageType = "user") => handlers.before_agent_start?.({ messageType, prompt: "do the work" }, {}),
    settle: () => Promise.all(pending),
  };
}

describe("herdr-thread-name", () => {
  const before = process.env.HC_TERMINAL_ID;
  beforeEach(() => {
    process.env.HC_TERMINAL_ID = "t7";
  });
  afterEach(() => {
    if (before === undefined) delete process.env.HC_TERMINAL_ID;
    else process.env.HC_TERMINAL_ID = before;
  });

  it("does nothing outside a herdr-core terminal", () => {
    delete process.env.HC_TERMINAL_ID;
    const f = fakePi();
    herdrThreadName(f.pi as any);
    assert.equal(f.tools.length, 0);
  });

  it("asks an unnamed interactive session to name itself and clears a stale label", async () => {
    const f = fakePi();
    herdrThreadName(f.pi as any);
    await f.start();
    assert.ok(f.active().includes("name_session"));
    assert.deepEqual(f.calls, [{ command: "hc", args: ["label", "t7", "pi.session="] }]);
  });

  it("labels a named session and leaves the tool off", async () => {
    const f = fakePi({ name: "SRE-1127 CloudSearch TF import" });
    herdrThreadName(f.pi as any);
    await f.start();
    assert.ok(!f.active().includes("name_session"));
    assert.deepEqual(f.calls[0], { command: "hc", args: ["label", "t7", "pi.session=SRE-1127 CloudSearch TF import"] });
  });

  it("names the session through the tool, then labels it and renames a numbered tab", async () => {
    const f = fakePi();
    herdrThreadName(f.pi as any);
    await f.start();
    const result = await f.tools[0].execute("call-1", { name: "  #5380   Aurora TF import \n" });
    await f.settle();
    assert.equal(result.details.name, "#5380 Aurora TF import");
    assert.ok(!f.active().includes("name_session"));
    assert.deepEqual(f.calls.slice(1), [
      { command: "hc", args: ["label", "t7", "pi.session=#5380 Aurora TF import"] },
      { command: "herdr-app", args: ["ls"] },
      { command: "herdr-app", args: ["do", "tab.rename", "--id", "tb1", "--name", "#5380 Aurora TF import"] },
    ]);
  });

  it("asks for a name with the first prompt of an unnamed session, once", async () => {
    const f = fakePi();
    herdrThreadName(f.pi as any);
    await f.start();
    const first: any = await f.prompt();
    assert.equal(first.message.customType, "herdr-thread-name");
    assert.equal(first.message.display, false);
    assert.match(first.message.content, /name_session/);
    assert.equal(await f.prompt(), undefined);
  });

  it("asks again in the next session", async () => {
    const f = fakePi();
    herdrThreadName(f.pi as any);
    await f.start();
    await f.prompt();
    await f.start();
    assert.ok(await f.prompt());
  });

  it("does not ask a named session, or for a message an extension sent", async () => {
    const named = fakePi({ name: "SRE-1252 GCP owner grant" });
    herdrThreadName(named.pi as any);
    await named.start();
    assert.equal(await named.prompt(), undefined);

    const f = fakePi();
    herdrThreadName(f.pi as any);
    await f.start();
    assert.equal(await f.prompt("custom"), undefined);
  });

  it("rejects an empty name", async () => {
    const f = fakePi();
    herdrThreadName(f.pi as any);
    await assert.rejects(() => f.tools[0].execute("call-1", { name: "   " }));
  });

  it("keeps a tab someone named", async () => {
    const f = fakePi({ herdrLs: ls({ tb1: ["worker", ["t7"]] }) });
    herdrThreadName(f.pi as any);
    await f.start();
    await f.rename("ArgoCD GitOps");
    assert.ok(!f.calls.some((c) => c.args[1] === "tab.rename"));
  });

  it("ignores print, json and rpc modes", async () => {
    const f = fakePi();
    herdrThreadName(f.pi as any);
    await f.start("print");
    await f.rename("Anything");
    assert.equal(await f.prompt(), undefined);
    assert.deepEqual(f.calls, []);
    assert.ok(!f.active().includes("name_session"));
  });

  it("survives hc and herdr-app failing", async () => {
    const f = fakePi();
    f.pi.exec = async () => {
      throw new Error("ENOENT");
    };
    herdrThreadName(f.pi as any);
    await f.start();
    await f.rename("Still fine");
  });
});

describe("tabToRename", () => {
  it("renames a numbered tab with this terminal alone in it", () => {
    assert.equal(tabToRename(ls({ tb1: ["2", ["t7"]] }), "t7"), "tb1");
  });

  it("keeps a named tab", () => {
    assert.equal(tabToRename(ls({ tb1: ["pi handoff", ["t7"]] }), "t7"), null);
  });

  it("keeps a tab this terminal shares", () => {
    assert.equal(tabToRename(ls({ tb1: ["1", ["t7", "t8"]] }), "t7"), null);
  });

  it("finds nothing for a terminal that is not shown", () => {
    assert.equal(tabToRename(ls({ tb1: ["1", ["t8"]] }), "t7"), null);
    assert.equal(tabToRename(undefined, "t7"), null);
  });
});

describe("cleanName", () => {
  it("makes one trimmed line of at most 60 characters", () => {
    assert.equal(cleanName("  a\n b\t c  "), "a b c");
    assert.equal(cleanName("x".repeat(80)).length, 60);
  });
});
