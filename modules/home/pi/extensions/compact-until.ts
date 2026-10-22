import type {
  AgentToolResult,
  ExtensionAPI,
  MessageRenderOptions,
  Theme,
  ToolRenderers,
  ToolRenderResultOptions,
} from "@earendil-works/pi-coding-agent";
import { getMarkdownTheme, keyHint } from "@earendil-works/pi-coding-agent";
import type { Component, TuiMouseEvent, TuiMouseEventResult } from "@earendil-works/pi-tui";
import { Box, Container, Markdown, Text, truncateToWidth } from "@earendil-works/pi-tui";

// Compact transcript rendering for joelhooks/pi-until.
//
// pi-until registers no renderers, so Pi draws every wake message as full
// Markdown (a recurring wake repeats its whole instruction, up to 20k chars)
// and every `until` call as its raw arguments. This extension only changes how
// those rows are drawn: collapsed, each is at most three width-truncated lines;
// expanded (app.tools.expand, ctrl+o by default, or a click on the row), it
// shows the complete content and details. Message content, details, tool arguments and results, execution
// and scheduling are untouched, so the model reads exactly what it did before.
//
// Payloads come from session history, so every field is optional and checked:
// old sessions, other pi-until versions, and partial results must still render.
// A renderer that throws falls back to Pi's default rendering.

// pi 1.3.0 does not export ToolRenderContext by name.
type ToolRenderContext = Parameters<NonNullable<ToolRenderers["renderCall"]>>[2];

export const WAKE_TYPES = ["pi-until", "pi-until-recurring"] as const;
export const TOOL_NAME = "until";

// ---------------------------------------------------------------------------
// Summaries: plain data, no terminal knowledge.

/** The receipt fields a summary reads. pi-until's WatchReceipt, all optional. */
export interface Receipt {
  readonly id?: string;
  readonly status?: string;
  readonly kind?: string;
  readonly label?: string;
  readonly attempts?: number;
  readonly deliveries?: number;
  readonly missedTicks?: number;
  readonly nextDueAt?: string;
  readonly lastExitCode?: number;
  readonly lastCheckKilled?: boolean;
  readonly defect?: string;
  readonly quickRef?: string;
}

/** Semantic tone for a segment; rendering maps it to a theme color. */
export type Tone = "accent" | "success" | "warning" | "error" | "muted" | "text";

export interface Segment {
  readonly text: string;
  readonly tone: Tone;
}

/** A compact view: one headline and an optional dim detail line. */
export interface Summary {
  readonly headline: readonly Segment[];
  readonly detail?: string;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const str = (value: unknown): string | undefined =>
  typeof value === "string" && value.length > 0 ? value : undefined;

const num = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

/** Reads a receipt-shaped record. Needs at least an id or a status. */
export function readReceipt(value: unknown): Receipt | undefined {
  if (!isRecord(value)) return undefined;
  const receipt: Receipt = {
    id: str(value.id),
    status: str(value.status),
    kind: str(value.kind),
    label: str(value.label),
    attempts: num(value.attempts),
    deliveries: num(value.deliveries),
    missedTicks: num(value.missedTicks),
    nextDueAt: str(value.nextDueAt),
    lastExitCode: num(value.lastExitCode),
    lastCheckKilled: value.lastCheckKilled === true ? true : undefined,
    defect: str(value.defect),
    quickRef: str(value.quickRef),
  };
  return receipt.id === undefined && receipt.status === undefined ? undefined : receipt;
}

/** The text of message or tool-result content, as the model read it. */
export function contentText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .flatMap((part) =>
      isRecord(part) && part.type === "text" && typeof part.text === "string" ? [part.text] : [],
    )
    .join("\n");
}

/**
 * One terminal-safe line: escape sequences and control characters dropped,
 * whitespace runs (tabs, newlines) collapsed to one space.
 */
export function oneLine(text: string): string {
  return text
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
    .replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/** The number of lines in a payload, for the "N lines" hint. */
export function lineCount(text: string): number {
  const trimmed = text.trim();
  return trimmed.length === 0 ? 0 : trimmed.split("\n").length;
}

/** "2026-10-22T14:05:00.000Z" -> "14:05:00Z"; anything else passes through. */
export function clock(iso: string): string {
  const match = /T(\d{2}:\d{2}:\d{2})(?:\.\d+)?Z$/.exec(iso);
  return match ? `${match[1]}Z` : iso;
}

/** The first non-empty line of a payload, minus Markdown heading marks. */
export function firstLine(text: string): string {
  const line = text.split("\n").find((candidate) => candidate.trim().length > 0) ?? "";
  return oneLine(line.replace(/^#+\s*/, ""));
}

const STATUS_TONES = new Map<string, Tone>([
  ["running", "accent"],
  ["started", "accent"],
  ["wake", "accent"],
  ["succeeded", "success"],
  ["completed", "success"],
  ["failed", "error"],
  ["timedOut", "warning"],
  ["expired", "warning"],
  ["cancelled", "warning"],
]);

const statusSegment = (status: string): Segment => ({
  text: oneLine(status),
  tone: STATUS_TONES.get(status) ?? "text",
});

const sep = (text: string, tone: Tone = "muted"): Segment[] => [
  { text: " · ", tone: "muted" },
  { text, tone },
];

const count = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/** Headline segments shared by wakes and tool receipts. */
function receiptSegments(receipt: Receipt, status: string | undefined): Segment[] {
  const segments: Segment[] = [];
  if (receipt.label !== undefined) segments.push(...sep(oneLine(receipt.label), "text"));
  if (receipt.kind === "recurring") {
    if (receipt.deliveries !== undefined) {
      segments.push(...sep(count(receipt.deliveries, "delivery", "deliveries")));
    }
    if (receipt.missedTicks !== undefined && receipt.missedTicks > 0) {
      segments.push(...sep(`${receipt.missedTicks} missed`, "warning"));
    }
    if (receipt.nextDueAt !== undefined) segments.push(...sep(`next ${clock(receipt.nextDueAt)}`));
  } else if (receipt.attempts !== undefined) {
    segments.push(...sep(count(receipt.attempts, "check", "checks")));
  }
  if (receipt.lastExitCode !== undefined) {
    segments.push(...sep(`exit ${receipt.lastExitCode}`, receipt.lastExitCode === 0 ? "muted" : "warning"));
  }
  if (receipt.lastCheckKilled === true) segments.push(...sep("check killed", "warning"));
  if (receipt.defect !== undefined) segments.push(...sep(oneLine(receipt.defect), "error"));
  if (receipt.id !== undefined) segments.push(...sep(oneLine(receipt.id)));
  if (status !== undefined) return [statusSegment(status), ...segments];
  // No status: drop the separator in front of the first segment.
  return segments.slice(1);
}

/**
 * Pulls receipt fields out of the text pi-until sends, for messages whose
 * details are missing or come from an older pi-until.
 */
export function receiptFromText(text: string): Receipt | undefined {
  const field = (pattern: RegExp) => pattern.exec(text)?.[1]?.trim();
  const int = (value: string | undefined) => (value === undefined ? undefined : Number(value));
  const header = /^pi-until watch (\S+): (\S+)\s*$/m.exec(text);
  const packetId = field(/^- Watch: `([^`]+)`/m);
  const id = header?.[1] ?? packetId;
  if (id === undefined) return undefined;
  const nextDue = field(/^-? ?Next due: (\S+)/m);
  return {
    id,
    status: header?.[2] ?? field(/^- Status: (\S+)/m),
    kind: field(/^Kind: (\S+)/m) ?? (packetId === undefined ? undefined : "recurring"),
    label: field(/^Label: (.+)$/m),
    attempts: int(field(/^Checks: (\d+)/m)),
    deliveries: int(field(/^-? ?Deliver(?:y|ies): (\d+)/m)),
    missedTicks: int(field(/^-? ?Missed ticks: (\d+)/m)),
    nextDueAt: nextDue === undefined || nextDue === "none" ? undefined : nextDue,
    lastExitCode: int(field(/^Last exit code: (-?\d+)/m)),
    defect: field(/^Failure: (.+)$/m),
    quickRef: /^## Quick reference\n(.+)$/m.exec(text)?.[1]?.trim() ?? field(/^Quick ref: (.+)$/m),
  };
}

/**
 * Summary of a pi-until wake message. Current pi-until sends details as
 * { followUpId, receipt }; a bare receipt or plain text works too.
 */
export function summarizeWake(customType: string, details: unknown, text: string): Summary {
  const receipt =
    (isRecord(details) ? readReceipt(details.receipt) : undefined) ??
    readReceipt(details) ??
    receiptFromText(text);
  if (receipt === undefined) {
    return { headline: [{ text: firstLine(text) || "(empty wake)", tone: "text" }] };
  }
  const recurring = customType === "pi-until-recurring" || receipt.kind === "recurring";
  // A recurring wake's receipt says "running"; what happened is a delivery.
  const status = recurring && receipt.status === "running" ? "wake" : receipt.status;
  const detail = recurring && receipt.quickRef !== undefined ? oneLine(receipt.quickRef) : undefined;
  return { headline: receiptSegments(receipt, status), detail };
}

/** Summary of an `until` call: action and target, plus one detail line for start and repeat. */
export function summarizeCall(args: unknown): Summary {
  const a = isRecord(args) ? args : {};
  const action = str(a.action);
  const rest: Segment[] = [];
  const target = str(a.id) ?? str(a.label);
  if (target !== undefined) rest.push({ text: ` ${oneLine(target)}`, tone: "accent" });
  const interval = num(a.intervalSeconds);
  if (interval !== undefined) rest.push(...sep(`every ${interval}s`));
  const timeout = num(a.timeoutSeconds);
  if (timeout !== undefined) rest.push(...sep(`for ${timeout}s`));
  if (a.immediate === true) rest.push(...sep("now"));
  if (str(a.wake) === "notify") rest.push(...sep("notify"));

  let detail: string | undefined;
  const condition = str(a.condition);
  if (condition !== undefined) detail = `$ ${oneLine(condition)}`;
  else if (action === "repeat") {
    const ref = str(a.quickRef) ?? str(a.instruction);
    if (ref !== undefined) detail = oneLine(ref);
  }
  return { headline: [{ text: oneLine(action ?? "…"), tone: "text" }, ...rest], detail };
}

/** Summary of an `until` tool result for the given call action. */
export function summarizeResult(
  action: string | undefined,
  details: unknown,
  text: string,
  isError: boolean,
): Summary {
  if (isError) return { headline: [{ text: firstLine(text) || "failed", tone: "error" }] };
  if (isRecord(details) && Array.isArray(details.watches)) {
    const receipts = details.watches.flatMap((watch) => readReceipt(watch) ?? []);
    if (receipts.length === 0) return { headline: [{ text: "no watches", tone: "muted" }] };
    const byStatus = new Map<string, number>();
    for (const receipt of receipts) {
      const status = receipt.status ?? "unknown";
      byStatus.set(status, (byStatus.get(status) ?? 0) + 1);
    }
    const headline: Segment[] = [{ text: count(receipts.length, "watch", "watches"), tone: "text" }];
    for (const [status, n] of byStatus) headline.push({ text: ` · ${n} `, tone: "muted" }, statusSegment(status));
    return { headline };
  }
  const receipt = readReceipt(details) ?? receiptFromText(text);
  if (receipt === undefined) return { headline: [{ text: firstLine(text) || "(no output)", tone: "text" }] };
  const started = (action === "start" || action === "repeat") && receipt.status === "running";
  return { headline: receiptSegments(receipt, started ? "started" : receipt.status) };
}

// ---------------------------------------------------------------------------
// Rendering.

/** Lines that never wrap: each is cut to the render width. Bounds collapsed rows. */
export class TruncatedLines implements Component {
  private readonly lines: readonly string[];

  constructor(lines: readonly string[]) {
    this.lines = lines;
  }

  render(width: number): string[] {
    const max = Math.max(1, width);
    return this.lines.map((line) => truncateToWidth(line, max));
  }

  invalidate(): void {
    // Lines are rebuilt by the renderer on every call; nothing is cached.
  }
}

/** A Box whose side padding shrinks so content keeps at least one column. */
class FitBox extends Box {
  private readonly maxPaddingX: number;
  private appliedPaddingX: number;

  constructor(paddingX: number, paddingY: number, bgFn: (text: string) => string) {
    super(paddingX, paddingY, bgFn);
    this.maxPaddingX = paddingX;
    this.appliedPaddingX = paddingX;
  }

  override render(width: number): string[] {
    const paddingX = Math.min(this.maxPaddingX, Math.max(0, Math.floor((width - 1) / 2)));
    if (paddingX !== this.appliedPaddingX) {
      this.appliedPaddingX = paddingX;
      this.setPaddingX(paddingX);
    }
    return super.render(width);
  }
}

const paint = (theme: Theme, segments: readonly Segment[]) =>
  segments.map((segment) => theme.fg(segment.tone, segment.text)).join("");

const expandHint = (hidden: number) =>
  hidden > 0 ? `… ${count(hidden, "line", "lines")}, ${keyHint("app.tools.expand", "to expand")}` : "";

/** Pretty JSON for expanded details; JSON escapes control characters. */
export function detailsJson(details: unknown): string | undefined {
  if (details === undefined) return undefined;
  try {
    return JSON.stringify(details, null, 2);
  } catch {
    return String(details);
  }
}

/** `key: value` lines for every argument; multi-line values are indented, never cut. */
export function formatArgs(args: unknown): string {
  if (!isRecord(args)) return args === undefined ? "" : (detailsJson(args) ?? "");
  return Object.entries(args)
    .map(([key, value]) => {
      const text = typeof value === "string" ? value : (detailsJson(value) ?? String(value));
      return `${key}: ${text.replace(/\r/g, "").split("\n").join("\n  ")}`;
    })
    .join("\n");
}

type WakeMessage = { customType: string; content: unknown; details?: unknown };

function buildWake(message: WakeMessage, expanded: boolean, outputPad: number, theme: Theme): Component {
  const text = contentText(message.content);
  const summary = summarizeWake(message.customType, message.details, text);
  const label = theme.fg("customMessageLabel", theme.bold(`[${message.customType}]`));
  const headline = `${label} ${paint(theme, summary.headline)}`;
  const box = new FitBox(outputPad, expanded ? 1 : 0, (line) => theme.bg("customMessageBg", line));

  if (!expanded) {
    const lines = [headline];
    if (summary.detail) lines.push(theme.fg("dim", summary.detail));
    const hint = expandHint(lineCount(text));
    if (hint) lines.push(theme.fg("muted", hint));
    box.addChild(new TruncatedLines(lines));
    return box;
  }

  box.addChild(new TruncatedLines([headline]));
  box.addChild(new Text("", 0, 0));
  box.addChild(
    new Markdown(text, 0, 0, getMarkdownTheme(), { color: (line) => theme.fg("customMessageText", line) }),
  );
  const json = detailsJson(message.details);
  if (json !== undefined) {
    box.addChild(new Text("", 0, 0));
    box.addChild(new Text(theme.fg("dim", `details:\n${json}`), 0, 0));
  }
  return box;
}

/**
 * Per-message expansion. `global` is the app-wide state (ctrl+o) the row was
 * last drawn with; `clicked` is a click's override. Pi rebuilds the row on
 * every theme change and global toggle, so the state lives outside the
 * component, keyed by the message object Pi keeps for the row.
 */
interface WakeState {
  global: boolean;
  clicked?: boolean;
}

const wakeStates = new WeakMap<object, WakeState>();

/**
 * A wake row that toggles on a left click, like Pi's own collapsible rows
 * (branch and compaction summaries, skills). Pi's custom-message row has no
 * click region of its own. A global ctrl+o clears the click, as it does there.
 */
export class WakeRow implements Component {
  private readonly message: WakeMessage;
  private readonly state: WakeState;
  private readonly outputPad: number;
  private readonly theme: Theme;
  private built: { expanded: boolean; component: Component } | undefined;

  constructor(message: WakeMessage, state: WakeState, outputPad: number, theme: Theme) {
    this.message = message;
    this.state = state;
    this.outputPad = outputPad;
    this.theme = theme;
  }

  get expanded(): boolean {
    return this.state.clicked ?? this.state.global;
  }

  render(width: number): string[] {
    const expanded = this.expanded;
    if (this.built?.expanded !== expanded) {
      this.built = { expanded, component: buildWake(this.message, expanded, this.outputPad, this.theme) };
    }
    return this.built.component.render(width);
  }

  handleMouse(event: TuiMouseEvent): TuiMouseEventResult | undefined {
    if (event.type !== "click" || event.button !== "left") return undefined;
    this.state.clicked = !this.expanded;
    return { handled: true };
  }

  invalidate(): void {
    this.built = undefined;
  }
}

function renderWake(message: WakeMessage, options: MessageRenderOptions, theme: Theme): Component {
  let state = wakeStates.get(message);
  if (state === undefined || state.global !== options.expanded) {
    state = { global: options.expanded };
    wakeStates.set(message, state);
  }
  return new WakeRow(message, state, options.outputPad, theme);
}

function renderCall(args: unknown, theme: Theme, context: ToolRenderContext): Component {
  const summary = summarizeCall(args);
  const headline = `${theme.fg("toolTitle", theme.bold(`${TOOL_NAME} `))}${paint(theme, summary.headline)}`;
  if (!context.expanded) {
    const lines = [headline];
    if (summary.detail) lines.push(theme.fg("dim", summary.detail));
    return new TruncatedLines(lines);
  }
  const container = new Container();
  container.addChild(new TruncatedLines([headline]));
  const full = formatArgs(args);
  if (full) container.addChild(new Text(theme.fg("muted", full), 0, 0));
  return container;
}

function renderResult(
  result: AgentToolResult<unknown>,
  options: ToolRenderResultOptions,
  theme: Theme,
  context: ToolRenderContext,
): Component {
  const text = contentText(result?.content);
  const action = isRecord(context.args) ? str(context.args.action) : undefined;
  if (options.isPartial && text.length === 0 && result?.details === undefined) {
    return new TruncatedLines([theme.fg("muted", "running…")]);
  }
  const summary = summarizeResult(action, result?.details, text, context.isError);
  const headline = paint(theme, summary.headline) + (options.isPartial ? theme.fg("muted", " (partial)") : "");
  if (!options.expanded) {
    const hidden = lineCount(text) - 1;
    return new TruncatedLines(hidden > 0 ? [headline, theme.fg("muted", expandHint(hidden))] : [headline]);
  }
  const container = new Container();
  container.addChild(new TruncatedLines([headline]));
  if (text) container.addChild(new Text(theme.fg("toolOutput", text), 0, 0));
  const json = detailsJson(result?.details);
  if (json !== undefined) container.addChild(new Text(theme.fg("dim", `details:\n${json}`), 0, 0));
  return container;
}

export const untilRenderers: ToolRenderers = {
  renderShell: "default",
  renderCall,
  renderResult,
};

export default function compactUntil(pi: ExtensionAPI) {
  for (const customType of WAKE_TYPES) {
    pi.registerMessageRenderer(customType, renderWake);
  }
  // Keep whatever else the registered tool defines; only the drawing changes.
  pi.registerToolRenderer((toolName, next) =>
    toolName === TOOL_NAME ? { ...next(), ...untilRenderers } : next(),
  );
}
