import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import {
  getAgentDir,
  type ExtensionAPI,
  type ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "claude-subscription-usage";
const USAGE_URL = "https://api.anthropic.com/api/oauth/usage";
const OAUTH_BETA = "oauth-2025-04-20";
const REFRESH_INTERVAL_MS = 5 * 60 * 1000;
const MIN_FETCH_INTERVAL_MS = 30 * 1000;
const TURN_REFRESH_DELAY_MS = 2 * 1000;
const AUTH_STATUS_TIMEOUT_MS = 5 * 1000;
const REQUEST_TIMEOUT_MS = 15 * 1000;
const MAX_RESPONSE_BYTES = 64 * 1024;

interface UsageWindow {
  utilization: number;
  resets_at: string | null;
}

interface ClaudeUsage {
  five_hour: UsageWindow | null;
  seven_day: UsageWindow | null;
  seven_day_opus?: UsageWindow | null;
  seven_day_sonnet?: UsageWindow | null;
  fable: UsageWindow | null;
}

interface ClaudeCredentials {
  claudeAiOauth?: {
    accessToken?: unknown;
  };
}

interface ClaudeAuthStatus {
  loggedIn?: unknown;
  authMethod?: unknown;
  apiProvider?: unknown;
  orgId?: unknown;
  subscriptionType?: unknown;
}

interface ClaudeBridgeConfig {
  provider?: {
    pathToClaudeCodeExecutable?: unknown;
  };
}

type UsageColor = "success" | "warning" | "error";
type RefreshResult = "fresh" | "cached" | "stale" | "unavailable" | "inactive";

function credentialsPath(): string {
  const configDir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
  return join(configDir, ".credentials.json");
}

async function readJsonFile<T>(path: string): Promise<T | undefined> {
  try {
    return JSON.parse(await readFile(path, "utf8")) as T;
  } catch {
    return undefined;
  }
}

async function readAccessToken(authMethod: string): Promise<string | undefined> {
  if (authMethod === "oauth_token") {
    const token = process.env.CLAUDE_CODE_OAUTH_TOKEN;
    return token && token.length > 0 ? token : undefined;
  }

  const credentials = await readJsonFile<ClaudeCredentials>(credentialsPath());
  const token = credentials?.claudeAiOauth?.accessToken;
  return typeof token === "string" && token.length > 0 ? token : undefined;
}

async function claudeExecutable(): Promise<string> {
  // Only the user-owned global config is trusted for automatic execution.
  // A repository-local override must never select a binary that runs on startup.
  const globalConfig = await readJsonFile<ClaudeBridgeConfig>(
    join(getAgentDir(), "claude-bridge.json"),
  );
  const configured = globalConfig?.provider?.pathToClaudeCodeExecutable;
  return typeof configured === "string" && configured.length > 0
    ? configured
    : "claude";
}

async function getSubscriptionCredential(
  pi: ExtensionAPI,
  ctx: ExtensionContext,
  signal: AbortSignal,
): Promise<{ token: string; identity: string } | undefined> {
  try {
    const executable = await claudeExecutable();
    const result = await pi.exec(executable, ["auth", "status", "--json"], {
      cwd: ctx.cwd,
      signal,
      timeout: AUTH_STATUS_TIMEOUT_MS,
    });
    if (result.code !== 0) return undefined;

    const status = JSON.parse(result.stdout) as ClaudeAuthStatus;
    const authMethod =
      typeof status.authMethod === "string" ? status.authMethod : undefined;
    const isSubscription =
      status.loggedIn === true &&
      status.apiProvider === "firstParty" &&
      ((authMethod === "claude.ai" &&
        typeof status.subscriptionType === "string" &&
        status.subscriptionType.length > 0) ||
        authMethod === "oauth_token");
    if (!isSubscription || !authMethod) return undefined;

    const token = await readAccessToken(authMethod);
    if (!token) return undefined;

    const tokenFingerprint = createHash("sha256")
      .update(token)
      .digest("hex")
      .slice(0, 16);
    const orgId = typeof status.orgId === "string" ? status.orgId : "oauth-token";
    return { token, identity: `${orgId}:${tokenFingerprint}` };
  } catch {
    return undefined;
  }
}

function isUsageWindow(value: unknown): value is UsageWindow {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<UsageWindow>;
  return (
    typeof candidate.utilization === "number" &&
    Number.isFinite(candidate.utilization) &&
    (candidate.resets_at === null || typeof candidate.resets_at === "string")
  );
}

function parseFableWindow(value: unknown): UsageWindow | null {
  if (!Array.isArray(value)) return null;

  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const limit = item as Record<string, unknown>;
    if (limit.kind !== "weekly_scoped") continue;

    const scope = limit.scope;
    if (!scope || typeof scope !== "object") continue;
    const model = (scope as Record<string, unknown>).model;
    if (!model || typeof model !== "object") continue;
    const displayName = (model as Record<string, unknown>).display_name;
    if (typeof displayName !== "string" || displayName.toLowerCase() !== "fable") {
      continue;
    }

    const percent = limit.percent;
    const resetsAt = limit.resets_at;
    if (typeof percent !== "number" || !Number.isFinite(percent)) return null;
    if (resetsAt !== undefined && resetsAt !== null && typeof resetsAt !== "string") {
      return null;
    }
    return { utilization: percent, resets_at: resetsAt ?? null };
  }

  return null;
}

function parseUsage(value: unknown): ClaudeUsage | undefined {
  if (!value || typeof value !== "object") return undefined;
  const candidate = value as Record<string, unknown>;
  const parseWindow = (name: string): UsageWindow | null | undefined => {
    const window = candidate[name];
    if (window === null || window === undefined) return window;
    return isUsageWindow(window) ? window : undefined;
  };

  const fiveHour = parseWindow("five_hour");
  const sevenDay = parseWindow("seven_day");
  if (fiveHour === undefined || sevenDay === undefined) return undefined;

  return {
    five_hour: fiveHour,
    seven_day: sevenDay,
    seven_day_opus: parseWindow("seven_day_opus"),
    seven_day_sonnet: parseWindow("seven_day_sonnet"),
    fable: parseFableWindow(candidate.limits),
  };
}

async function readBoundedBody(response: Response): Promise<string | undefined> {
  if (!response.body) return undefined;

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      totalBytes += value.byteLength;
      if (totalBytes > MAX_RESPONSE_BYTES) {
        await reader.cancel();
        return undefined;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  return Buffer.concat(chunks.map((chunk) => Buffer.from(chunk))).toString("utf8");
}

async function fetchUsage(
  accessToken: string,
  controller: AbortController,
): Promise<ClaudeUsage | undefined> {
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(USAGE_URL, {
      method: "GET",
      signal: controller.signal,
      headers: {
        accept: "application/json",
        authorization: `Bearer ${accessToken}`,
        "anthropic-beta": OAUTH_BETA,
        "anthropic-dangerous-direct-browser-access": "true",
        "user-agent": "claude-cli/pi-claude-bridge",
        "x-app": "cli",
      },
    });
    if (!response.ok) {
      await response.body?.cancel();
      return undefined;
    }

    const body = await readBoundedBody(response);
    return body ? parseUsage(JSON.parse(body)) : undefined;
  } catch {
    return undefined;
  } finally {
    clearTimeout(timeout);
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

function formatReset(resetAt: string | null): string {
  if (!resetAt) return "unknown";
  const remainingMs = new Date(resetAt).getTime() - Date.now();
  if (!Number.isFinite(remainingMs) || remainingMs <= 0) return "now";

  const minutes = Math.ceil(remainingMs / 60_000);
  const days = Math.floor(minutes / (24 * 60));
  const hours = Math.floor((minutes % (24 * 60)) / 60);
  const restMinutes = minutes % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${restMinutes}m`;
  return `${restMinutes}m`;
}

function modelSpecificWindow(
  usage: ClaudeUsage,
  modelId: string | undefined,
): { label: "opus" | "sonnet"; window: UsageWindow } | undefined {
  // Fable has its own top-level window, so never double-report it here.
  if (modelId?.toLowerCase().includes("fable")) return undefined;

  const normalized = modelId?.toLowerCase() ?? "";
  if (normalized.includes("opus") && usage.seven_day_opus) {
    return { label: "opus", window: usage.seven_day_opus };
  }
  if (normalized.includes("sonnet") && usage.seven_day_sonnet) {
    return { label: "sonnet", window: usage.seven_day_sonnet };
  }
  return undefined;
}

function statusParts(
  usage: ClaudeUsage,
  modelId: string | undefined,
): Array<{ label: string; percent: number }> {
  const parts: Array<{ label: string; percent: number }> = [];
  if (usage.five_hour) {
    parts.push({ label: "5h", percent: clampPercent(usage.five_hour.utilization) });
  }
  if (usage.seven_day) {
    parts.push({ label: "7d", percent: clampPercent(usage.seven_day.utilization) });
  }
  if (usage.fable) {
    parts.push({ label: "fable", percent: clampPercent(usage.fable.utilization) });
  }

  const modelWindow = modelSpecificWindow(usage, modelId);
  if (modelWindow) {
    parts.push({
      label: modelWindow.label,
      percent: clampPercent(modelWindow.window.utilization),
    });
  }
  return parts;
}

function isClaudeBridge(ctx: ExtensionContext): boolean {
  return ctx.model?.provider === "claude-bridge";
}

export default function claudeSubscriptionUsage(pi: ExtensionAPI) {
  let active = false;
  let activeModelId: string | undefined;
  let lastUsage: ClaudeUsage | undefined;
  let lastUsageStale = false;
  let credentialIdentity: string | undefined;
  let lastFetchAt = 0;
  let requestSequence = 0;
  let activeRequest:
    | {
        id: number;
        controller: AbortController;
        promise: Promise<RefreshResult>;
      }
    | undefined;
  let pollTimer: ReturnType<typeof setInterval> | undefined;
  let turnTimer: ReturnType<typeof setTimeout> | undefined;

  const clearStatus = (ctx: ExtensionContext) => {
    if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
  };

  const renderStatus = (ctx: ExtensionContext) => {
    if (!ctx.hasUI || !active) return;
    const theme = ctx.ui.theme;
    const parts = lastUsage ? statusParts(lastUsage, activeModelId) : [];
    if (parts.length === 0) {
      ctx.ui.setStatus(STATUS_KEY, theme.fg("dim", "[usage] n/a"));
      return;
    }

    // Each window is colored by its own severity so a single hot quota stands
    // out instead of being averaged into one label-wide color.
    const rendered = parts
      .map(
        (part) =>
          theme.fg("dim", `${part.label}:`) +
          theme.fg(usageColor(part.percent), `${Math.round(part.percent)}%`),
      )
      .join(" ");
    const suffix = lastUsageStale ? theme.fg("dim", " stale") : "";
    ctx.ui.setStatus(
      STATUS_KEY,
      `${theme.fg("dim", "[usage] ")}${rendered}${suffix}`,
    );
  };

  const cancelRequest = () => {
    requestSequence += 1;
    activeRequest?.controller.abort();
    activeRequest = undefined;
  };

  const clearCachedIdentity = () => {
    credentialIdentity = undefined;
    lastUsage = undefined;
    lastUsageStale = false;
  };

  const refresh = async (
    ctx: ExtensionContext,
    options: { force?: boolean } = {},
  ): Promise<RefreshResult> => {
    if (!active || !ctx.hasUI) {
      clearStatus(ctx);
      return "inactive";
    }
    if (process.env.PI_OFFLINE === "1") {
      lastUsageStale = lastUsage !== undefined;
      renderStatus(ctx);
      return lastUsage ? "stale" : "unavailable";
    }
    if (!options.force && Date.now() - lastFetchAt < MIN_FETCH_INTERVAL_MS) {
      renderStatus(ctx);
      if (!lastUsage) return "unavailable";
      return lastUsageStale ? "stale" : "cached";
    }
    if (activeRequest && !options.force) return activeRequest.promise;
    if (activeRequest) cancelRequest();

    const id = ++requestSequence;
    const controller = new AbortController();
    lastFetchAt = Date.now();
    const promise = (async (): Promise<RefreshResult> => {
      const credential = await getSubscriptionCredential(
        pi,
        ctx,
        controller.signal,
      );
      if (!active || id !== requestSequence) return "inactive";
      if (!credential) {
        clearCachedIdentity();
        renderStatus(ctx);
        return "unavailable";
      }

      if (credentialIdentity !== credential.identity) {
        lastUsage = undefined;
        lastUsageStale = false;
        credentialIdentity = credential.identity;
      }

      const usage = await fetchUsage(credential.token, controller);
      if (!active || id !== requestSequence) return "inactive";
      if (usage) {
        lastUsage = usage;
        lastUsageStale = false;
        renderStatus(ctx);
        return "fresh";
      }

      lastUsageStale = lastUsage !== undefined;
      renderStatus(ctx);
      return lastUsage ? "stale" : "unavailable";
    })();

    activeRequest = { id, controller, promise };
    try {
      return await promise;
    } finally {
      if (activeRequest?.id === id) activeRequest = undefined;
    }
  };

  pi.on("session_start", async (_event, ctx) => {
    active = isClaudeBridge(ctx);
    activeModelId = active ? ctx.model?.id : undefined;
    if (active) void refresh(ctx, { force: true });
    else clearStatus(ctx);

    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(() => void refresh(ctx), REFRESH_INTERVAL_MS);
    pollTimer.unref?.();
  });

  pi.on("model_select", async (event, ctx) => {
    active = event.model.provider === "claude-bridge";
    activeModelId = active ? event.model.id : undefined;
    if (active) {
      clearStatus(ctx);
      void refresh(ctx, { force: true });
    } else {
      cancelRequest();
      lastUsageStale = lastUsage !== undefined;
      clearStatus(ctx);
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (!active) return;
    if (turnTimer) clearTimeout(turnTimer);
    turnTimer = setTimeout(() => void refresh(ctx), TURN_REFRESH_DELAY_MS);
    turnTimer.unref?.();
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    active = false;
    cancelRequest();
    if (pollTimer) clearInterval(pollTimer);
    if (turnTimer) clearTimeout(turnTimer);
    pollTimer = undefined;
    turnTimer = undefined;
    clearStatus(ctx);
  });

  pi.registerCommand("claude-usage", {
    description: "Refresh and show Claude Code subscription usage",
    handler: async (_args, ctx) => {
      active = isClaudeBridge(ctx);
      activeModelId = active ? ctx.model?.id : undefined;
      if (!active) {
        ctx.ui.notify(
          "Select a claude-bridge model to view Claude subscription usage.",
          "warning",
        );
        return;
      }

      const result = await refresh(ctx, { force: true });
      if (!lastUsage) {
        ctx.ui.notify("Claude subscription usage is unavailable.", "warning");
        return;
      }

      const lines: string[] = [];
      if (lastUsage.five_hour) {
        lines.push(
          `5h: ${Math.round(clampPercent(lastUsage.five_hour.utilization))}% used; resets in ${formatReset(lastUsage.five_hour.resets_at)}`,
        );
      }
      if (lastUsage.seven_day) {
        lines.push(
          `Weekly: ${Math.round(clampPercent(lastUsage.seven_day.utilization))}% used; resets in ${formatReset(lastUsage.seven_day.resets_at)}`,
        );
      }
      if (lastUsage.fable) {
        lines.push(
          `Fable weekly: ${Math.round(clampPercent(lastUsage.fable.utilization))}% used; resets in ${formatReset(lastUsage.fable.resets_at)}`,
        );
      }
      const modelWindow = modelSpecificWindow(lastUsage, activeModelId);
      if (modelWindow) {
        lines.push(
          `${modelWindow.label === "opus" ? "Opus" : "Sonnet"} weekly: ${Math.round(clampPercent(modelWindow.window.utilization))}% used; resets in ${formatReset(modelWindow.window.resets_at)}`,
        );
      }

      const prefix = result === "fresh" ? "" : "Cached (refresh failed): ";
      ctx.ui.notify(
        `${prefix}${lines.join("\n") || "Claude subscription usage has no active windows."}`,
        result === "fresh" ? "info" : "warning",
      );
    },
  });
}
