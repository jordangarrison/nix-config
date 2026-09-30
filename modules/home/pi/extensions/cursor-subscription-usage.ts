import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

// Sibling of claude-subscription-usage.ts and codex-subscription-usage.ts.
// Shown while a cursor model is active. Cursor bills a monthly included pool
// (total) plus a named-model API pool, not 5h/7d windows.
//
// The dashboard call needs the Cursor login session, not pi's Cursor API key
// (`/login cursor` stores a `crsr_` key, and that key is rejected here).
// cursor-agent writes the session to the same auth.json path this reads.
const STATUS_KEY = "0-usage-cursor";
const PROVIDER = "cursor";
const USAGE_URL =
  "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";
const REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const MIN_FETCH_INTERVAL_MS = 30 * 1000;
const TURN_REFRESH_DELAY_MS = 2 * 1000;
const REQUEST_TIMEOUT_MS = 15 * 1000;

interface UsageWindow {
  label: string;
  percent: number;
}

interface CursorUsage {
  windows: UsageWindow[];
  resetsAtMs: number | undefined;
  includedCents: number | undefined;
  limitCents: number | undefined;
  bonusCents: number | undefined;
  autoPercent: number | undefined;
  onDemandUsedCents: number | undefined;
  onDemandLimitCents: number | undefined;
}

interface CursorAuthFile {
  accessToken?: unknown;
}

type UsageColor = "success" | "warning" | "error";

function authFilePath(): string {
  const home = homedir();
  switch (process.platform) {
    case "win32": {
      const appData = process.env.APPDATA || join(home, "AppData", "Roaming");
      return join(appData, "Cursor", "auth.json");
    }
    case "darwin":
      return join(home, ".cursor", "auth.json");
    default: {
      const base = process.env.XDG_CONFIG_HOME || join(home, ".config");
      return join(base, "cursor", "auth.json");
    }
  }
}

function clampPercent(value: number): number {
  return Math.max(0, Math.min(100, value));
}

function usageColor(percent: number): UsageColor {
  if (percent >= 90) return "error";
  if (percent >= 70) return "warning";
  return "success";
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function epochMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && /^[0-9]+$/.test(value)) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function percentField(value: unknown): number | undefined {
  const parsed = finiteNumber(value);
  return parsed === undefined ? undefined : clampPercent(parsed);
}

function onDemandUsed(spend: Record<string, unknown>): {
  used: number | undefined;
  limit: number | undefined;
} {
  const limit = finiteNumber(spend.individualLimit);
  const used = finiteNumber(spend.individualUsed);
  if (used !== undefined) return { used, limit };
  const remaining = finiteNumber(spend.individualRemaining);
  if (limit !== undefined && remaining !== undefined) {
    return { used: Math.max(0, limit - remaining), limit };
  }
  return { used: undefined, limit };
}

function parseUsage(payload: unknown): CursorUsage | undefined {
  if (!payload || typeof payload !== "object") return undefined;
  const root = payload as Record<string, unknown>;
  const plan =
    root.planUsage && typeof root.planUsage === "object"
      ? (root.planUsage as Record<string, unknown>)
      : undefined;
  const spend =
    root.spendLimitUsage && typeof root.spendLimitUsage === "object"
      ? (root.spendLimitUsage as Record<string, unknown>)
      : undefined;

  const total = plan ? percentField(plan.totalPercentUsed) : undefined;
  const api = plan ? percentField(plan.apiPercentUsed) : undefined;
  const auto = plan ? percentField(plan.autoPercentUsed) : undefined;
  const includedCents = plan ? finiteNumber(plan.includedSpend) : undefined;
  const limitCents = plan ? finiteNumber(plan.limit) : undefined;
  const bonusCents = plan ? finiteNumber(plan.bonusSpend) : undefined;
  const onDemand = spend ? onDemandUsed(spend) : { used: undefined, limit: undefined };

  const windows: UsageWindow[] = [];
  if (total !== undefined) windows.push({ label: "total", percent: total });
  if (api !== undefined) windows.push({ label: "api", percent: api });
  if (
    windows.length === 0 &&
    includedCents !== undefined &&
    limitCents !== undefined &&
    limitCents > 0
  ) {
    windows.push({
      label: "included",
      percent: clampPercent((includedCents / limitCents) * 100),
    });
  }
  if (
    onDemand.used !== undefined &&
    onDemand.limit !== undefined &&
    onDemand.limit > 0 &&
    onDemand.used > 0
  ) {
    windows.push({
      label: "od",
      percent: clampPercent((onDemand.used / onDemand.limit) * 100),
    });
  }
  if (windows.length === 0) return undefined;

  return {
    windows,
    resetsAtMs: epochMillis(root.billingCycleEnd),
    includedCents,
    limitCents,
    bonusCents,
    autoPercent: auto,
    onDemandUsedCents: onDemand.used,
    onDemandLimitCents: onDemand.limit,
  };
}

async function readAccessToken(): Promise<string | undefined> {
  try {
    const auth = JSON.parse(await readFile(authFilePath(), "utf8")) as CursorAuthFile;
    const token = auth.accessToken;
    return typeof token === "string" && token.length > 0 ? token : undefined;
  } catch {
    return undefined;
  }
}

async function fetchUsage(
  token: string,
  signal: AbortSignal,
): Promise<CursorUsage | undefined> {
  const response = await fetch(USAGE_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "Connect-Protocol-Version": "1",
      "User-Agent": "pi-cursor-usage",
    },
    body: "{}",
    signal: AbortSignal.any([signal, AbortSignal.timeout(REQUEST_TIMEOUT_MS)]),
  });
  if (!response.ok) {
    await response.body?.cancel();
    return undefined;
  }
  return parseUsage(await response.json());
}

function formatReset(resetsAtMs: number | undefined): string {
  if (resetsAtMs === undefined) return "unknown";
  const minutes = Math.ceil((resetsAtMs - Date.now()) / 60_000);
  if (minutes <= 0) return "now";
  const days = Math.floor(minutes / (24 * 60));
  const hours = Math.floor((minutes % (24 * 60)) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  return `${minutes}m`;
}

function formatCents(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function detailLines(usage: CursorUsage): string[] {
  const lines = usage.windows.map(
    (window) => `${window.label}: ${Math.round(window.percent)}% used`,
  );
  const total = usage.windows.find((window) => window.label === "total")?.percent;
  if (
    usage.autoPercent !== undefined &&
    (total === undefined || Math.abs(usage.autoPercent - total) >= 1)
  ) {
    lines.push(`auto: ${Math.round(usage.autoPercent)}% used`);
  }
  lines.push(`resets in ${formatReset(usage.resetsAtMs)}`);
  if (
    usage.includedCents !== undefined &&
    usage.limitCents !== undefined &&
    usage.limitCents > 0
  ) {
    lines.push(
      `plan spend: ${formatCents(usage.includedCents)} included of ${formatCents(usage.limitCents)}`,
    );
  }
  if (usage.bonusCents !== undefined && usage.bonusCents > 0) {
    lines.push(`bonus spend: ${formatCents(usage.bonusCents)}`);
  }
  if (usage.onDemandLimitCents !== undefined && usage.onDemandLimitCents > 0) {
    lines.push(
      `on-demand: ${formatCents(usage.onDemandUsedCents ?? 0)} of ${formatCents(usage.onDemandLimitCents)}`,
    );
  }
  return lines;
}

export default function cursorSubscriptionUsage(pi: ExtensionAPI) {
  let active = false;
  let lastUsage: CursorUsage | undefined;
  let lastUsageStale = false;
  let lastAuthMissing = false;
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
    const windows = lastUsage?.windows ?? [];
    if (windows.length === 0) {
      ctx.ui.setStatus(STATUS_KEY, theme.fg("dim", "[usage] n/a"));
      return;
    }
    const rendered = windows
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
    let usage: CursorUsage | undefined;
    let authMissing = false;
    try {
      const token = await readAccessToken();
      if (!token) {
        authMissing = true;
      } else if (!current.signal.aborted) {
        usage = await fetchUsage(token, current.signal);
      }
    } catch {
      usage = undefined;
    }
    if (controller !== current || !active) return;
    lastAuthMissing = authMissing;
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

  pi.registerCommand("cursor-usage", {
    description: "Refresh and show Cursor plan usage",
    handler: async (_args, ctx) => {
      active = ctx.model?.provider === PROVIDER;
      if (!active) {
        ctx.ui.notify("Select a cursor model to view Cursor usage.", "warning");
        return;
      }
      await refresh(ctx, true);
      if (!lastUsage) {
        ctx.ui.notify(
          lastAuthMissing
            ? "Cursor usage needs a Cursor login. Run `agent login`. Pi's Cursor API key cannot read plan usage."
            : "Cursor subscription usage is unavailable.",
          "warning",
        );
        return;
      }
      const prefix = lastUsageStale ? "Cached (refresh failed): " : "";
      ctx.ui.notify(
        `${prefix}${detailLines(lastUsage).join("\n")}`,
        lastUsageStale ? "warning" : "info",
      );
    },
  });
}
