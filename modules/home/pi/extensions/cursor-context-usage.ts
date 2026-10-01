import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Pi's footer and auto-compaction both read assistant usage as the current
// context window. Cursor's run result sums every internal model call, and even
// the last call includes that agent's private tool transcript. Either number
// routinely exceeds Pi's catalog window, so Pi summarizes its own history.
// That summary does not shrink the Cursor agent.
//
// This extension keeps the last single-call snapshot, then caps the fields Pi
// compares against the window so a successful Cursor reply cannot compact.
// Manual `/compact` still runs. A local edit in the installed
// @pixu1980/pi-cursor package keeps the last call at the source; the cap here
// still applies if that package is reinstalled without the edit.

const FALLBACK_CONTEXT_WINDOW = 128_000;
// Pi's default compaction reserve. Usage at or under `window - reserve` does
// not cross shouldCompact, and input + cacheRead at that budget does not
// cross the silent-overflow check.
const PI_COMPACTION_RESERVE = 16_384;

interface UsageSnapshot {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  totalTokens: number;
  reasoning?: number;
  cost?: {
    input: number;
    output: number;
    cacheRead: number;
    cacheWrite: number;
    total: number;
  };
}

interface CursorMessage {
  role?: string;
  provider?: string;
  api?: string;
  model?: string;
  usage?: unknown;
}

export function contextWindowFromModelId(modelId: string | undefined): number | undefined {
  const match = /@(\d+(?:\.\d+)?)([km])$/i.exec(modelId ?? "");
  if (!match) return undefined;
  const amount = Number(match[1]);
  if (!Number.isFinite(amount)) return undefined;
  return Math.round(amount * (match[2]!.toLowerCase() === "m" ? 1_000_000 : 1_000));
}

function finite(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function readUsage(usage: unknown): UsageSnapshot | undefined {
  if (!usage || typeof usage !== "object") return undefined;
  const value = usage as Record<string, unknown>;
  const input = finite(value.input);
  const output = finite(value.output);
  const cacheRead = finite(value.cacheRead);
  const cacheWrite = finite(value.cacheWrite);
  if (
    input === undefined ||
    output === undefined ||
    cacheRead === undefined ||
    cacheWrite === undefined
  ) {
    return undefined;
  }

  const reasoning = finite(value.reasoning);
  const costRecord =
    value.cost && typeof value.cost === "object"
      ? (value.cost as Record<string, unknown>)
      : undefined;
  const cost = costRecord
    ? {
        input: finite(costRecord.input) ?? 0,
        output: finite(costRecord.output) ?? 0,
        cacheRead: finite(costRecord.cacheRead) ?? 0,
        cacheWrite: finite(costRecord.cacheWrite) ?? 0,
        total: finite(costRecord.total) ?? 0,
      }
    : undefined;

  return {
    input,
    output,
    cacheRead,
    cacheWrite,
    totalTokens: finite(value.totalTokens) ?? input + output + cacheRead + cacheWrite,
    ...(reasoning === undefined ? {} : { reasoning }),
    ...(cost ? { cost } : {}),
  };
}

function promptTokens(usage: Pick<UsageSnapshot, "input" | "cacheRead">): number {
  return usage.input + usage.cacheRead;
}

/** A single model call cannot grow by more than one full window in one step. */
export function isCumulativeReplacement(
  previous: UsageSnapshot | undefined,
  next: UsageSnapshot,
  contextWindow: number,
): boolean {
  if (!previous || contextWindow <= 0) return false;
  const previousPrompt = promptTokens(previous);
  if (previousPrompt <= 0) return false;
  return promptTokens(next) > previousPrompt + contextWindow;
}

/** Usage Pi will treat as context. Above the compaction budget, shrink to it. */
export function fitUsageForPiContext(usage: UsageSnapshot, contextWindow: number): UsageSnapshot {
  const budget = Math.max(1, contextWindow - PI_COMPACTION_RESERVE);
  const prompt = promptTokens(usage);
  if (prompt <= budget && usage.totalTokens <= budget) return usage;

  const scale = prompt > budget && prompt > 0 ? budget / prompt : 1;
  const input = Math.floor(usage.input * scale);
  let cacheRead = Math.floor(usage.cacheRead * scale);
  if (input + cacheRead > budget) cacheRead = Math.max(0, budget - input);
  const roomForWrite = Math.max(0, budget - input - cacheRead);
  const cacheWrite = Math.min(usage.cacheWrite, roomForWrite);

  return {
    ...usage,
    input,
    cacheRead,
    cacheWrite,
    totalTokens: Math.min(input + usage.output + cacheRead + cacheWrite, budget),
  };
}

export function noteCursorUsage(
  current: UsageSnapshot | undefined,
  next: UsageSnapshot,
  contextWindow: number,
): UsageSnapshot | undefined {
  if (next.input + next.output + next.cacheRead + next.cacheWrite <= 0) return current;
  if (isCumulativeReplacement(current, next, contextWindow)) return current;
  return next;
}

function isCursorAssistant(message: CursorMessage): boolean {
  return message.role === "assistant" && (message.provider === "cursor" || message.api === "cursor-sdk");
}

function messageOf(event: unknown): CursorMessage | undefined {
  if (!event || typeof event !== "object") return undefined;
  const record = event as Record<string, unknown>;
  const candidate = record.partial ?? record.message ?? record.error;
  if (!candidate || typeof candidate !== "object") return undefined;
  return candidate as CursorMessage;
}

export default function cursorContextUsage(pi: ExtensionAPI) {
  let contextWindow = FALLBACK_CONTEXT_WINDOW;
  let contextUsage: UsageSnapshot | undefined;

  const rememberWindow = (modelId: string | undefined) => {
    const parsed = contextWindowFromModelId(modelId);
    if (parsed) contextWindow = parsed;
  };

  const observe = (message: CursorMessage | undefined) => {
    if (!message || !isCursorAssistant(message)) return;
    rememberWindow(message.model);
    const usage = readUsage(message.usage);
    if (!usage) return;
    contextUsage = noteCursorUsage(contextUsage, usage, contextWindow);
  };

  // Snapshot at enqueue time. The stream reuses one message object, so a later
  // read of the same event sees whatever usage was written last.
  void import("@earendil-works/pi-ai")
    .then((ai) => {
      const stream = ai.createAssistantMessageEventStream();
      const proto = Object.getPrototypeOf(stream) as {
        push?: (event: unknown) => void;
        cursorContextUsageHooked?: boolean;
      };
      if (!proto.push || proto.cursorContextUsageHooked) return;
      const original = proto.push;
      proto.push = function push(event: unknown) {
        const record = event as { type?: string } | null;
        const message = messageOf(event);
        if (record?.type === "start" && message && isCursorAssistant(message)) {
          contextUsage = undefined;
        }
        observe(message);
        if (record?.type === "done" || record?.type === "error") {
          const message = messageOf(event);
          const finalUsage = message ? readUsage(message.usage) : undefined;
          if (message && finalUsage) {
            const chosen =
              contextUsage && isCumulativeReplacement(contextUsage, finalUsage, contextWindow)
                ? { ...contextUsage, cost: finalUsage.cost ?? contextUsage.cost }
                : finalUsage;
            message.usage = fitUsageForPiContext(chosen, contextWindow);
          }
        }
        return original.call(this, event);
      };
      proto.cursorContextUsageHooked = true;
    })
    .catch(() => {
      // message_end below still corrects the stored message.
    });

  pi.on("message_update", async (event) => {
    observe(event.message as CursorMessage);
    const partial = (event.assistantMessageEvent as { partial?: CursorMessage } | undefined)?.partial;
    observe(partial);
  });

  pi.on("message_end", async (event) => {
    const message = event.message as CursorMessage & Record<string, unknown>;
    if (!isCursorAssistant(message)) return;
    rememberWindow(message.model);
    const finalUsage = readUsage(message.usage);
    const snapshot = contextUsage;
    contextUsage = undefined;
    if (!finalUsage) return;
    const chosen =
      snapshot && isCumulativeReplacement(snapshot, finalUsage, contextWindow)
        ? { ...snapshot, cost: finalUsage.cost ?? snapshot.cost }
        : finalUsage;
    const fitted = fitUsageForPiContext(chosen, contextWindow);
    if (
      fitted.input === finalUsage.input &&
      fitted.output === finalUsage.output &&
      fitted.cacheRead === finalUsage.cacheRead &&
      fitted.cacheWrite === finalUsage.cacheWrite &&
      fitted.totalTokens === finalUsage.totalTokens
    ) {
      return;
    }
    return {
      message: {
        ...message,
        usage: fitted,
      },
    };
  });

  // Messages already saved over the window still trip the check on the next
  // prompt, before message_end can rewrite them. Cancel that attempt.
  // `/compact` uses reason "manual" and is left alone. A later auto-compact
  // whose estimate fits the catalog window is left alone too.
  pi.on("session_before_compact", async (event, ctx) => {
    if (event.reason === "manual") return;
    if (ctx.model?.provider !== "cursor") return;
    const tokensBefore = event.preparation?.tokensBefore;
    const window = contextWindowFromModelId(ctx.model?.id) ?? contextWindow;
    if (typeof tokensBefore !== "number" || tokensBefore <= window) return;
    return { cancel: true };
  });
}
