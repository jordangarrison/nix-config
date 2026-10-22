// Regression tests for modules/home/pi/extensions/compact-until.ts. Run with
// `nix build .#checks.x86_64-linux.pi-extensions`, which lays the extension
// out next to this file and a node_modules with the real pi-tui.
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { visibleWidth } from "@earendil-works/pi-tui";
import compactUntil, {
  receiptFromText,
  summarizeCall,
  summarizeResult,
  summarizeWake,
  untilRenderers,
} from "../extensions/compact-until.ts";

// --- fakes -----------------------------------------------------------------

// Real escape sequences, so width checks cover styled output.
const theme = {
  fg: (_token: string, text: string) => `\x1b[38;5;2m${text}\x1b[39m`,
  bg: (_token: string, text: string) => `\x1b[48;5;4m${text}\x1b[49m`,
  bold: (text: string) => `\x1b[1m${text}\x1b[22m`,
} as any;

const strip = (line: string) => line.replace(/\x1b\[[0-9;]*m/g, "");

type Renderer = (...args: any[]) => any;

function load() {
  const messageRenderers = new Map<string, Renderer>();
  const toolResolvers: Renderer[] = [];
  compactUntil({
    registerMessageRenderer: (type: string, renderer: Renderer) => messageRenderers.set(type, renderer),
    registerToolRenderer: (resolver: Renderer) => toolResolvers.push(resolver),
  } as any);
  return { messageRenderers, toolResolvers };
}

const { messageRenderers, toolResolvers } = load();

function renderWake(message: Record<string, unknown>, expanded: boolean, width: number): string[] {
  const renderer = messageRenderers.get(message.customType as string);
  assert.ok(renderer, `renderer for ${message.customType}`);
  return renderer(message, { expanded, outputPad: 1 }, theme).render(width);
}

const context = (args: unknown, overrides: Record<string, unknown> = {}) =>
  ({
    args,
    toolCallId: "call-1",
    invalidate: () => {},
    lastComponent: undefined,
    state: {},
    cwd: "/tmp",
    executionStarted: true,
    argsComplete: true,
    isPartial: false,
    expanded: false,
    showImages: false,
    isError: false,
    durationMs: undefined,
    outputPad: 1,
    ...overrides,
  }) as any;

function renderCall(args: unknown, expanded: boolean, width: number, overrides = {}): string[] {
  return untilRenderers.renderCall!(args, theme, context(args, { expanded, ...overrides })).render(width);
}

function renderResult(
  args: unknown,
  result: unknown,
  { expanded = false, isPartial = false, isError = false, width = 80 } = {},
): string[] {
  return untilRenderers.renderResult!(
    result as any,
    { expanded, isPartial },
    theme,
    context(args, { expanded, isPartial, isError }),
  ).render(width);
}

function assertFits(lines: string[], width: number) {
  for (const line of lines) {
    assert.ok(visibleWidth(line) <= width, `line wider than ${width}: ${JSON.stringify(strip(line))}`);
  }
}

// --- fixtures (shapes copied from joelhooks/pi-until extensions/pi-until.ts) --

const WIDTHS = [1, 2, 5, 12, 24, 40, 80, 200];
const marker = (i: number) => `step-${i}-marker`;
const longInstruction = Array.from({ length: 400 }, (_, i) => `- ${marker(i)}: check the queue and act`).join("\n");

const recurringReceipt = {
  attempts: 3,
  deliveries: 7,
  deliveryPending: false,
  expiresAt: "2026-10-23T00:00:00.000Z",
  id: "w-recurring",
  intervalMs: 300_000,
  kind: "recurring",
  label: "triage review channel",
  missedTicks: 1,
  nextDueAt: "2026-10-22T14:05:00.000Z",
  quickRef: "Review new PRs in #infra-reviews",
  reloads: 0,
  startedAt: "2026-10-22T10:00:00.000Z",
  status: "running",
  wake: "agent",
};

const recurringPacket = [
  "# Recurring follow-up",
  "",
  "## Instruction",
  longInstruction,
  "",
  "## Quick reference",
  "Review new PRs in #infra-reviews",
  "",
  "## Receipt",
  "- Watch: `w-recurring`",
  "- Delivery: 7",
  "- Missed ticks: 1",
  "- Delivered: 2026-10-22T14:00:00.000Z",
  "- Next due: 2026-10-22T14:05:00.000Z",
  "- Expires: 2026-10-23T00:00:00.000Z",
  "- Survived reloads: 0",
  "",
  "## Control",
  "Call `until` with `action=complete` and `id=w-recurring` when the goal is achieved.",
].join("\n");

const recurringWake = {
  role: "custom",
  customType: "pi-until-recurring",
  content: recurringPacket,
  display: true,
  details: { followUpId: "f-1", receipt: recurringReceipt },
  timestamp: 1,
};

const terminalReceipt = {
  attempts: 4,
  deliveries: 0,
  deliveryPending: false,
  id: "w-ci",
  intervalMs: 30_000,
  kind: "until",
  label: "CI green",
  lastExitCode: 0,
  missedTicks: 0,
  reloads: 0,
  startedAt: "2026-10-22T10:00:00.000Z",
  status: "succeeded",
  wake: "agent",
};

const terminalText = [
  "The condition was true when checked. Before acting, confirm the task still needs work.",
  "",
  "pi-until watch w-ci: succeeded",
  "Kind: until",
  "Label: CI green",
  "Checks: 4",
  "Last exit code: 0",
].join("\n");

const terminalWake = {
  role: "custom",
  customType: "pi-until",
  content: terminalText,
  display: true,
  details: { followUpId: "f-2", receipt: terminalReceipt },
  timestamp: 2,
};

// --- registration ----------------------------------------------------------

describe("registration", () => {
  it("renders both wake types and only the until tool", () => {
    assert.deepEqual([...messageRenderers.keys()].sort(), ["pi-until", "pi-until-recurring"]);
    assert.equal(toolResolvers.length, 1);
    const other = { renderCall: () => "other" };
    assert.equal(toolResolvers[0]("bash", () => other), other);
    assert.equal(toolResolvers[0]("subagent", () => undefined), undefined);
  });

  it("keeps the registered tool's other fields and works without one", () => {
    const base = { label: "Until", renderShell: "self" };
    const resolved = toolResolvers[0]("until", () => base);
    assert.equal(resolved.label, "Until");
    assert.equal(resolved.renderShell, "default");
    assert.equal(resolved.renderCall, untilRenderers.renderCall);
    assert.equal(toolResolvers[0]("until", () => undefined).renderResult, untilRenderers.renderResult);
  });
});

// --- wake messages ---------------------------------------------------------

describe("wake messages", () => {
  it("collapses a long recurring instruction to at most three lines", () => {
    const lines = renderWake(recurringWake, false, 120).map(strip);
    assert.ok(lines.length <= 3, `got ${lines.length} lines`);
    const text = lines.join("\n");
    assert.match(text, /\[pi-until-recurring\] wake · triage review channel · 7 deliveries · 1 missed/);
    assert.match(text, /Review new PRs in #infra-reviews/);
    assert.match(text, /ctrl\+o to expand/);
    assert.doesNotMatch(text, /step-1-marker/);
  });

  it("stays within every width, including very narrow ones", () => {
    for (const message of [recurringWake, terminalWake]) {
      for (const width of WIDTHS) {
        for (const expanded of [false, true]) {
          const lines = renderWake(message, expanded, width);
          assertFits(lines, width);
          if (!expanded) assert.ok(lines.length <= 3);
        }
      }
    }
  });

  it("cuts wide characters and control sequences safely", () => {
    const hostile = {
      ...terminalWake,
      details: { receipt: { ...terminalReceipt, label: "部署🚀\x1b]8;;http://x\x07link\x1b]8;;\x07\tdone\u0007" } },
    };
    for (const width of WIDTHS) assertFits(renderWake(hostile, false, width), width);
    const text = renderWake(hostile, false, 200).map(strip).join("\n");
    assert.match(text, /部署🚀link done/);
    assert.doesNotMatch(text, /\x07|\t/);
  });

  it("expands to the complete original content and details", () => {
    const text = renderWake(recurringWake, true, 100).map(strip).join("\n");
    for (let i = 0; i < 400; i++) assert.ok(text.includes(marker(i)), `missing ${marker(i)}`);
    assert.match(text, /Call `?until`? with `?action=complete`?/);
    assert.match(text, /"followUpId": "f-1"/);
    assert.match(text, /"quickRef": "Review new PRs in #infra-reviews"/);
  });

  it("summarizes a terminal wake from its receipt", () => {
    const text = renderWake(terminalWake, false, 120).map(strip).join("\n");
    assert.match(text, /\[pi-until\] succeeded · CI green · 4 checks · exit 0 · w-ci/);
    assert.doesNotMatch(text, /Before acting/);
  });

  it("falls back to the text when details are missing", () => {
    const { details: _ignored, ...bare } = terminalWake;
    const fromText = renderWake(bare, false, 120).map(strip).join("\n");
    assert.match(fromText, /succeeded · CI green · 4 checks · exit 0 · w-ci/);

    const recurringBare = { ...recurringWake, details: undefined };
    const recurringText = renderWake(recurringBare, false, 120).map(strip).join("\n");
    assert.match(recurringText, /wake|7 deliveries/);
    assert.match(recurringText, /w-recurring/);
    assert.match(recurringText, /Review new PRs/);

    const plain = { ...terminalWake, details: { unrelated: true }, content: "\n\n## Something else\nbody" };
    assert.match(renderWake(plain, false, 120).map(strip).join("\n"), /\[pi-until\] Something else/);

    const empty = { ...terminalWake, details: null, content: [] };
    assert.match(renderWake(empty, false, 120).map(strip).join("\n"), /\(empty wake\)/);
    assertFits(renderWake(empty, true, 10), 10);
  });

  it("toggles one row on a left click and keeps it across redraws", () => {
    const renderer = messageRenderers.get("pi-until-recurring")!;
    const message = structuredClone(recurringWake);
    const click = (row: any, overrides = {}) =>
      row.handleMouse({ type: "click", button: "left", x: 0, y: 0, screenX: 0, screenY: 0, width: 80, height: 3, shift: false, alt: false, ctrl: false, ...overrides });
    const text = (row: any) => row.render(80).map(strip).join("\n");

    const row = renderer(message, { expanded: false, outputPad: 1 }, theme);
    assert.ok(row.render(80).length <= 3);
    assert.equal(click(row, { button: "right" }), undefined);
    assert.equal(click(row, { type: "move" }), undefined);
    assert.ok(row.render(80).length <= 3);

    assert.deepEqual(click(row), { handled: true });
    assert.ok(text(row).includes(marker(399)));

    // Pi rebuilds the row on a theme change with the same global state.
    const rebuilt = renderer(message, { expanded: false, outputPad: 1 }, theme);
    assert.ok(text(rebuilt).includes(marker(399)));
    // Other rows are not affected.
    const other = renderer(structuredClone(recurringWake), { expanded: false, outputPad: 1 }, theme);
    assert.ok(other.render(80).length <= 3);

    click(rebuilt);
    assert.ok(rebuilt.render(80).length <= 3);
  });

  it("lets a global ctrl+o override a clicked row", () => {
    const renderer = messageRenderers.get("pi-until")!;
    const message = structuredClone(terminalWake);
    const clicked = renderer(message, { expanded: false, outputPad: 1 }, theme);
    clicked.handleMouse({ type: "click", button: "left", x: 0, y: 0, width: 80, height: 3 });
    assert.match(clicked.render(80).map(strip).join("\n"), /Before acting/);

    const expandedAll = renderer(message, { expanded: true, outputPad: 1 }, theme);
    assert.match(expandedAll.render(80).map(strip).join("\n"), /Before acting/);
    const collapsedAll = renderer(message, { expanded: false, outputPad: 1 }, theme);
    assert.doesNotMatch(collapsedAll.render(80).map(strip).join("\n"), /Before acting/);

    // A click on a globally expanded row collapses just that row.
    const row = renderer(message, { expanded: true, outputPad: 1 }, theme);
    row.handleMouse({ type: "click", button: "left", x: 0, y: 0, width: 80, height: 3 });
    assert.doesNotMatch(row.render(80).map(strip).join("\n"), /Before acting/);
  });

  it("reads array content and leaves the message untouched", () => {
    const message = structuredClone({ ...terminalWake, content: [{ type: "text", text: terminalText }] });
    const before = structuredClone(message);
    renderWake(message, false, 40);
    renderWake(message, true, 40);
    assert.deepEqual(message, before);
  });
});

// --- tool calls ------------------------------------------------------------

describe("until calls", () => {
  const start = {
    action: "start",
    label: "CI green",
    condition: `gh pr checks 42 --json state | jq -e 'all(.state == "SUCCESS")' ${"&& true ".repeat(200)}`,
    intervalSeconds: 30,
    timeoutSeconds: 3600,
  };
  const repeat = {
    action: "repeat",
    label: "triage",
    instruction: longInstruction,
    quickRef: "Review new PRs",
    intervalSeconds: 300,
    timeoutSeconds: 86400,
    immediate: true,
    contextRefs: [{ label: "canvas", target: "slack://canvas/1" }],
  };

  it("collapses start and repeat to a headline and one detail line", () => {
    const startLines = renderCall(start, false, 80).map(strip);
    assert.equal(startLines.length, 2);
    assert.match(startLines[0], /^until start CI green · every 30s · for 3600s/);
    assert.match(startLines[1], /^\$ gh pr checks 42/);

    const repeatLines = renderCall(repeat, false, 80).map(strip);
    assert.equal(repeatLines.length, 2);
    assert.match(repeatLines[0], /until repeat triage · every 300s · for 86400s · now/);
    assert.equal(repeatLines[1], "Review new PRs");
  });

  it("shows complete, status and cancel targets", () => {
    for (const action of ["complete", "status", "cancel"]) {
      assert.deepEqual(renderCall({ action, id: "w-1" }, false, 80).map(strip), [`until ${action} w-1`]);
    }
    assert.deepEqual(renderCall({ action: "list" }, false, 80).map(strip), ["until list"]);
  });

  it("expands to every argument in full", () => {
    const text = renderCall(repeat, true, 60).map(strip).join("\n");
    for (let i = 0; i < 400; i++) assert.ok(text.includes(marker(i)), `missing ${marker(i)}`);
    assert.match(text, /slack:\/\/canvas\/1/);
    const startText = renderCall(start, true, 60).map(strip).join("");
    assert.ok(startText.replace(/\s/g, "").includes(start.condition.replace(/\s/g, "")));
  });

  it("renders streaming, partial and malformed arguments within width", () => {
    for (const args of [undefined, null, {}, { action: "rep" }, { label: 5, intervalSeconds: "x" }, "raw"]) {
      for (const width of WIDTHS) {
        for (const expanded of [false, true]) {
          assertFits(renderCall(args, expanded, width, { argsComplete: false, executionStarted: false }), width);
        }
      }
    }
    assert.deepEqual(renderCall({}, false, 80).map(strip), ["until …"]);
  });
});

// --- tool results ----------------------------------------------------------

describe("until results", () => {
  const receiptText = (receipt: Record<string, unknown>) =>
    `pi-until watch ${receipt.id}: ${receipt.status}\nKind: ${receipt.kind}\nLabel: ${receipt.label}\nChecks: ${receipt.attempts}`;
  const resultOf = (receipt: Record<string, unknown>) => ({
    content: [{ type: "text", text: receiptText(receipt) }],
    details: receipt,
  });

  it("summarizes start, complete, status and cancel receipts", () => {
    const running = { ...recurringReceipt };
    assert.match(strip(renderResult({ action: "repeat" }, resultOf(running))[0]), /^started · triage review channel/);
    const completed = { ...recurringReceipt, status: "completed" };
    assert.match(strip(renderResult({ action: "complete", id: "w-recurring" }, resultOf(completed))[0]), /^completed ·/);
    assert.match(strip(renderResult({ action: "status", id: "w-ci" }, resultOf(terminalReceipt))[0]), /^succeeded · CI green · 4 checks/);
    const cancelled = { ...terminalReceipt, status: "cancelled", lastExitCode: 1 };
    assert.match(strip(renderResult({ action: "cancel", id: "w-ci" }, resultOf(cancelled))[0]), /^cancelled · CI green · 4 checks · exit 1 · w-ci/);
  });

  it("keeps collapsed results to a headline and one hint", () => {
    const lines = renderResult({ action: "status" }, resultOf(terminalReceipt)).map(strip);
    assert.equal(lines.length, 2);
    assert.match(lines[1], /3 lines, ctrl\+o to expand/);
  });

  it("counts list results by status", () => {
    const result = {
      content: [{ type: "text", text: "w-1\trunning\ta\tattempts=1\nw-2\tsucceeded\tb\tattempts=2" }],
      details: { watches: [{ id: "w-1", status: "running" }, { id: "w-2", status: "succeeded" }, { id: "w-3", status: "running" }] },
    };
    assert.match(strip(renderResult({ action: "list" }, result)[0]), /^3 watches · 2 running · 1 succeeded/);
    const none = { content: [{ type: "text", text: "No pi-until watches." }], details: { watches: [] } };
    assert.deepEqual(renderResult({ action: "list" }, none).map(strip), ["no watches"]);
  });

  it("shows errors by their first line", () => {
    const result = { content: [{ type: "text", text: "unknown pi-until watch: w-9\n    at stack" }], details: undefined };
    assert.match(strip(renderResult({ action: "status", id: "w-9" }, result, { isError: true })[0]), /^unknown pi-until watch: w-9/);
  });

  it("handles partial results and missing details", () => {
    assert.deepEqual(renderResult({ action: "start" }, { content: [] }, { isPartial: true }).map(strip), ["running…"]);
    assert.deepEqual(renderResult({ action: "start" }, undefined, { isPartial: true }).map(strip), ["running…"]);
    const partial = { content: [{ type: "text", text: "pi-until watch w-ci: running" }] };
    assert.match(strip(renderResult({ action: "start" }, partial, { isPartial: true })[0]), /started · w-ci \(partial\)/);
    const textOnly = { content: [{ type: "text", text: receiptText(terminalReceipt) }] };
    assert.match(strip(renderResult({ action: "status" }, textOnly)[0]), /^succeeded · CI green · 4 checks/);
    assert.deepEqual(renderResult({ action: "status" }, { content: [] }).map(strip), ["(no output)"]);
    assert.deepEqual(renderResult(undefined, { content: "Started." }).map(strip), ["Started."]);
  });

  it("stays within every width, collapsed and expanded", () => {
    const results = [resultOf(recurringReceipt), resultOf(terminalReceipt), { content: [] }, undefined];
    for (const result of results) {
      for (const width of WIDTHS) {
        for (const expanded of [false, true]) {
          for (const isPartial of [false, true]) {
            assertFits(renderResult({ action: "status" }, result, { expanded, isPartial, width }), width);
          }
        }
      }
    }
  });

  it("expands to the complete content and details", () => {
    const result = resultOf({ ...recurringReceipt, quickRef: longInstruction.slice(0, 2000) });
    const before = structuredClone(result);
    const text = renderResult({ action: "status" }, result, { expanded: true, width: 70 }).map(strip).join("\n");
    assert.match(text, /pi-until watch w-recurring: running/);
    assert.match(text, /Checks: 3/);
    assert.match(text, /"intervalMs": 300000/);
    assert.ok(text.includes(marker(20)));
    assert.deepEqual(result, before);
  });
});

// --- pure summaries --------------------------------------------------------

describe("summaries", () => {
  it("parse pi-until's receipt and packet text", () => {
    assert.deepEqual(receiptFromText(terminalText), {
      id: "w-ci",
      status: "succeeded",
      kind: "until",
      label: "CI green",
      attempts: 4,
      deliveries: undefined,
      missedTicks: undefined,
      nextDueAt: undefined,
      lastExitCode: 0,
      defect: undefined,
      quickRef: undefined,
    });
    const packet = receiptFromText(recurringPacket);
    assert.equal(packet?.kind, "recurring");
    assert.equal(packet?.deliveries, 7);
    assert.equal(packet?.quickRef, "Review new PRs in #infra-reviews");
    assert.equal(receiptFromText("nothing here"), undefined);
  });

  it("never throw on odd input", () => {
    for (const value of [undefined, null, 0, "", [], {}, { receipt: 5 }, { id: 3, status: [] }]) {
      summarizeWake("pi-until", value, "");
      summarizeCall(value);
      summarizeResult(undefined, value, "", false);
    }
  });
});
