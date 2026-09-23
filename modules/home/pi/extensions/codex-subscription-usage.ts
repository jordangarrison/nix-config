import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

// Sibling of claude-subscription-usage.ts: same "[usage] 5h:NN% 7d:NN%" footer
// (quota used, colored per window), shown while an openai-codex model is
// active. Pi sorts footer statuses by key, so "0-" keeps it leftmost.
const STATUS_KEY = "0-usage-codex";
const PROVIDER = "openai-codex";
const USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const MIN_FETCH_INTERVAL_MS = 30 * 1000;
const TURN_REFRESH_DELAY_MS = 2 * 1000;
const REQUEST_TIMEOUT_MS = 15 * 1000;

interface UsageWindow {
  label: string;
  percent: number;
  resetsAt: number | undefined;
}

interface ProviderAuth {
  apiKey?: string;
  headers?: Record<string, string>;
  baseUrl?: string;
}

interface AuthRegistry {
  getProviderAuth?(
    providerId: string,
  ): Promise<{ auth: ProviderAuth } | undefined>;
}

type UsageColor = "success" | "warning" | "error";

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, value));
}

function usageColor(percent: number): UsageColor {
  if (percent >= 90) return "error";
  if (percent >= 70) return "warning";
  return "success";
}

function windowLabel(seconds: number | undefined, fallback: string): string {
  if (!seconds || seconds <= 0) return fallback;
  const hours = Math.round(seconds / 3600);
  if (hours % 24 === 0) return `${hours / 24}d`;
  return `${hours}h`;
}

function parseWindow(raw: unknown, fallback: string): UsageWindow | undefined {
  if (!raw || typeof raw !== "object") return undefined;
  const value = raw as Record<string, unknown>;
  const used = Number(value.used_percent);
  if (!Number.isFinite(used)) return undefined;
  const seconds = Number(value.limit_window_seconds);
  const resetAt = Number(value.reset_at);
  return {
    label: windowLabel(Number.isFinite(seconds) ? seconds : undefined, fallback),
    percent: clampPercent(used),
    resetsAt: Number.isFinite(resetAt) ? resetAt : undefined,
  };
}

function parseUsage(payload: unknown): UsageWindow[] {
  if (!payload || typeof payload !== "object") return [];
  const limit = (payload as Record<string, unknown>).rate_limit;
  if (!limit || typeof limit !== "object") return [];
  const windows = limit as Record<string, unknown>;
  return [
    parseWindow(windows.primary_window, "5h"),
    parseWindow(windows.secondary_window, "7d"),
  ].filter((window): window is UsageWindow => window !== undefined);
}

function authorization(auth: ProviderAuth): string | undefined {
  for (const [name, value] of Object.entries(auth.headers ?? {})) {
    if (name.toLowerCase() === "authorization") return value;
  }
  return auth.apiKey ? `Bearer ${auth.apiKey}` : undefined;
}

async function fetchUsage(
  ctx: ExtensionContext,
  signal: AbortSignal,
): Promise<UsageWindow[] | undefined> {
  const registry = ctx.modelRegistry as unknown as AuthRegistry;
  const resolved = await registry.getProviderAuth?.(PROVIDER);
  if (!resolved) return undefined;
  // Never send a proxy or custom-endpoint credential to chatgpt.com.
  const baseUrl = resolved.auth.baseUrl;
  if (baseUrl && new URL(baseUrl).origin !== "https://chatgpt.com") {
    return undefined;
  }
  const header = authorization(resolved.auth);
  if (!header) return undefined;

  const response = await fetch(USAGE_URL, {
    headers: { Authorization: header, "User-Agent": "pi-codex-usage" },
    signal: AbortSignal.any([signal, AbortSignal.timeout(REQUEST_TIMEOUT_MS)]),
  });
  if (!response.ok) {
    await response.body?.cancel();
    return undefined;
  }
  const windows = parseUsage(await response.json());
  return windows.length > 0 ? windows : undefined;
}

function formatReset(resetsAt: number | undefined): string {
  if (resetsAt === undefined) return "unknown";
  const minutes = Math.ceil((resetsAt * 1000 - Date.now()) / 60_000);
  if (minutes <= 0) return "now";
  const days = Math.floor(minutes / (24 * 60));
  const hours = Math.floor((minutes % (24 * 60)) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  return `${minutes}m`;
}

export default function codexSubscriptionUsage(pi: ExtensionAPI) {
  let active = false;
  let lastUsage: UsageWindow[] | undefined;
  let lastUsageStale = false;
  let lastFetchAt = 0;
  let controller: AbortController | undefined;
  let pollTimer: ReturnType<typeof setInterval> | undefined;
  let turnTimer: ReturnType<typeof setTimeout> | undefined;

  const clearStatus = (ctx: ExtensionContext) => {
    if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
  };

  const renderStatus = (ctx: ExtensionContext) => {
    if (!ctx.hasUI || !active) return;
    const theme = ctx.ui.theme;
    if (!lastUsage) {
      ctx.ui.setStatus(STATUS_KEY, theme.fg("dim", "[usage] n/a"));
      return;
    }
    const rendered = lastUsage
      .map(
        (window) =>
          theme.fg("dim", `${window.label}:`) +
          theme.fg(usageColor(window.percent), `${Math.round(window.percent)}%`),
      )
      .join(" ");
    const suffix = lastUsageStale ? theme.fg("dim", " stale") : "";
    ctx.ui.setStatus(STATUS_KEY, `${theme.fg("dim", "[usage] ")}${rendered}${suffix}`);
  };

  const refresh = async (ctx: ExtensionContext, force = false) => {
    if (!active || !ctx.hasUI) return;
    if (process.env.PI_OFFLINE === "1") {
      lastUsageStale = lastUsage !== undefined;
      renderStatus(ctx);
      return;
    }
    if (!force && Date.now() - lastFetchAt < MIN_FETCH_INTERVAL_MS) return;

    controller?.abort();
    const current = new AbortController();
    controller = current;
    lastFetchAt = Date.now();
    let usage: UsageWindow[] | undefined;
    try {
      usage = await fetchUsage(ctx, current.signal);
    } catch {
      usage = undefined;
    }
    if (controller !== current || !active) return;
    if (usage) {
      lastUsage = usage;
      lastUsageStale = false;
    } else {
      lastUsageStale = lastUsage !== undefined;
    }
    renderStatus(ctx);
  };

  // Nothing awaits these, and pi has no unhandledRejection handler, so a throw
  // from a stale `ctx` must not take the agent down.
  const refreshInBackground = (ctx: ExtensionContext, force = false) =>
    void refresh(ctx, force).catch(() => {});

  pi.on("session_start", async (_event, ctx) => {
    active = ctx.model?.provider === PROVIDER;
    if (active) refreshInBackground(ctx, true);
    else clearStatus(ctx);

    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(() => refreshInBackground(ctx), REFRESH_INTERVAL_MS);
    pollTimer.unref?.();
  });

  pi.on("model_select", async (event, ctx) => {
    active = event.model.provider === PROVIDER;
    if (active) {
      renderStatus(ctx);
      refreshInBackground(ctx, true);
    } else {
      controller?.abort();
      controller = undefined;
      clearStatus(ctx);
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (!active) return;
    if (turnTimer) clearTimeout(turnTimer);
    turnTimer = setTimeout(() => refreshInBackground(ctx), TURN_REFRESH_DELAY_MS);
    turnTimer.unref?.();
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    active = false;
    controller?.abort();
    controller = undefined;
    if (pollTimer) clearInterval(pollTimer);
    if (turnTimer) clearTimeout(turnTimer);
    pollTimer = undefined;
    turnTimer = undefined;
    clearStatus(ctx);
  });

  pi.registerCommand("codex-usage", {
    description: "Refresh and show ChatGPT (Codex) subscription usage",
    handler: async (_args, ctx) => {
      active = ctx.model?.provider === PROVIDER;
      if (!active) {
        ctx.ui.notify("Select an openai-codex model to view Codex usage.", "warning");
        return;
      }
      await refresh(ctx, true);
      if (!lastUsage) {
        ctx.ui.notify("Codex subscription usage is unavailable.", "warning");
        return;
      }
      const lines = lastUsage.map(
        (window) =>
          `${window.label}: ${Math.round(window.percent)}% used; resets in ${formatReset(window.resetsAt)}`,
      );
      const prefix = lastUsageStale ? "Cached (refresh failed): " : "";
      ctx.ui.notify(`${prefix}${lines.join("\n")}`, lastUsageStale ? "warning" : "info");
    },
  });
}
