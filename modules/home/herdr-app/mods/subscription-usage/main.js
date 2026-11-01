// Claude, Codex, and xAI subscription windows.
// Reads local login files and calls the provider usage endpoints.
// Tokens stay in memory for the request. Shared state stores percents only.

import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, props, agents, spaces, run, window, keys, shared, setShared, openOverlay, closeOverlay, home, exec } from "herdr";
import * as fs from "fs/promises";

const KEY = "subscription.usage";
const REFRESH_MS = 5 * 60 * 1000;
const MIN_FETCH_MS = 30 * 1000;
const CLAUDE_URL = "https://api.anthropic.com/api/oauth/usage";
const CODEX_URL = "https://chatgpt.com/backend-api/wham/usage";
const XAI_URL = "https://cli-chat-proxy.grok.com/v1/billing?format=credits";

const join = (...parts) => parts.filter(Boolean).join("/").replace(/\/+/g, "/");

async function readJson(path) {
  try {
    return JSON.parse(await fs.readFile(path, "utf8"));
  } catch {
    return undefined;
  }
}

function clamp(value) {
  return Math.max(0, Math.min(100, value));
}

function finite(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function windowLabel(seconds, fallback) {
  if (!seconds || seconds < 3600) return fallback;
  const hours = Math.round(seconds / 3600);
  return hours % 24 === 0 ? `${hours / 24}d` : `${hours}h`;
}

function formatReset(at) {
  if (at == null) return "unknown";
  const ms = typeof at === "number" ? (at < 1e12 ? at * 1000 : at) : Date.parse(at);
  if (!Number.isFinite(ms)) return "unknown";
  const minutes = Math.ceil((ms - Date.now()) / 60000);
  if (minutes <= 0) return "now";
  const days = Math.floor(minutes / (24 * 60));
  const hours = Math.floor((minutes % (24 * 60)) / 60);
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  return `${minutes}m`;
}

function tone(t, percent) {
  if (percent >= 90) return t.blocked;
  if (percent >= 70) return t.ansi3;
  return t.done;
}

async function fetchJson(url, headers) {
  const response = await fetch(url, { headers });
  if (!response.ok) {
    try { await response.text(); } catch {}
    return undefined;
  }
  return response.json();
}

function claudeWindow(value) {
  if (!value || typeof value !== "object") return undefined;
  const utilization = finite(value.utilization);
  if (utilization === undefined) return undefined;
  return { label: "", percent: clamp(utilization), resetsAt: typeof value.resets_at === "string" ? value.resets_at : null };
}

function fableWindow(limits) {
  if (!Array.isArray(limits)) return undefined;
  for (const item of limits) {
    if (!item || item.kind !== "weekly_scoped") continue;
    const name = item.scope?.model?.display_name;
    if (typeof name !== "string" || name.toLowerCase() !== "fable") continue;
    const percent = finite(item.percent);
    if (percent === undefined) continue;
    return { label: "fable", percent: clamp(percent), resetsAt: typeof item.resets_at === "string" ? item.resets_at : null };
  }
  return undefined;
}

function claudeWindows(payload) {
  if (!payload || typeof payload !== "object") return [];
  const named = [
    ["5h", claudeWindow(payload.five_hour)],
    ["7d", claudeWindow(payload.seven_day)],
    ["fable", fableWindow(payload.limits)],
    ["opus", claudeWindow(payload.seven_day_opus)],
    ["sonnet", claudeWindow(payload.seven_day_sonnet)],
  ];
  return named.filter(([, window]) => window).map(([label, window]) => ({ ...window, label: window.label || label }));
}

async function claudeToken() {
  let dir = join(home(), ".claude");
  try {
    const result = await exec("claude", ["auth", "status", "--json"]);
    if (result.code === 0) {
      const status = JSON.parse(result.stdout);
      if (typeof status.configDirectory === "string" && status.configDirectory.startsWith("/")) dir = status.configDirectory;
      const method = status.authMethod;
      const subscribed = status.loggedIn === true && status.apiProvider === "firstParty"
        && ((method === "claude.ai" && typeof status.subscriptionType === "string" && status.subscriptionType.length > 0)
          || method === "oauth_token");
      if (!subscribed) return undefined;
      const envToken = typeof process !== "undefined" ? process.env?.CLAUDE_CODE_OAUTH_TOKEN : undefined;
      if (method === "oauth_token" && envToken) return envToken;
    } else {
      return undefined;
    }
  } catch {
    return undefined;
  }
  const credentials = await readJson(join(dir, ".credentials.json"));
  const token = credentials?.claudeAiOauth?.accessToken;
  return typeof token === "string" && token.length > 0 ? token : undefined;
}

async function loadClaude() {
  const token = await claudeToken();
  if (!token) return undefined;
  const payload = await fetchJson(CLAUDE_URL, {
    accept: "application/json",
    authorization: `Bearer ${token}`,
    "anthropic-beta": "oauth-2025-04-20",
    "anthropic-dangerous-direct-browser-access": "true",
    "user-agent": "claude-cli/pi-claude-bridge",
    "x-app": "cli",
  });
  const windows = claudeWindows(payload);
  return windows.length ? windows : undefined;
}

function codexWindow(raw, fallback) {
  if (!raw || typeof raw !== "object") return undefined;
  const used = finite(raw.used_percent);
  if (used === undefined) return undefined;
  return {
    label: windowLabel(finite(raw.limit_window_seconds), fallback),
    percent: clamp(used),
    resetsAt: finite(raw.reset_at) ?? null,
  };
}

function collectCodex(node, fallback) {
  if (!node || typeof node !== "object") return [];
  const direct = codexWindow(node, fallback);
  if (direct) return [direct];
  if (Array.isArray(node)) return node.flatMap((item, index) => collectCodex(item, `${fallback}${index + 1}`));
  return Object.entries(node).flatMap(([key, value]) => collectCodex(value, key.split("_").join(" ")));
}

async function codexAuth() {
  const codex = await readJson(join(home(), ".codex", "auth.json"));
  const fromCodex = codex?.tokens;
  if (typeof fromCodex?.access_token === "string" && fromCodex.access_token.length > 0) {
    return { token: fromCodex.access_token, account: typeof fromCodex.account_id === "string" ? fromCodex.account_id : undefined };
  }
  const pi = await readJson(join(home(), ".pi", "agent", "auth.json"));
  const fromPi = pi?.["openai-codex"];
  if (typeof fromPi?.access === "string" && fromPi.access.length > 0) {
    return { token: fromPi.access, account: typeof fromPi.accountId === "string" ? fromPi.accountId : undefined };
  }
  return undefined;
}

async function loadCodex() {
  const auth = await codexAuth();
  if (!auth) return undefined;
  const headers = { Authorization: `Bearer ${auth.token}`, "User-Agent": "herdr-subscription-usage" };
  if (auth.account) headers["ChatGPT-Account-Id"] = auth.account;
  const payload = await fetchJson(CODEX_URL, headers);
  if (!payload || typeof payload !== "object") return undefined;
  const windows = [
    ...collectCodex(payload.rate_limit, "limit"),
    ...collectCodex(payload.code_review_rate_limit, "review"),
    ...collectCodex(payload.additional_rate_limits, "extra"),
  ];
  return windows.length ? windows : undefined;
}

function tokenField(value) {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

async function xaiToken() {
  const pi = await readJson(join(home(), ".pi", "agent", "auth.json"));
  const fromPi = tokenField(pi?.xai?.access);
  if (fromPi) return fromPi;
  const grok = await readJson(join(home(), ".grok", "auth.json"));
  return tokenField(grok?.access) ?? tokenField(grok?.access_token) ?? tokenField(grok?.key) ?? tokenField(grok?.token);
}

function xaiWindow(payload) {
  const config = payload?.config;
  const percent = finite(config?.creditUsagePercent);
  if (percent === undefined) return undefined;
  const weekly = config?.currentPeriod?.type === "USAGE_PERIOD_TYPE_WEEKLY";
  const end = config?.currentPeriod?.end;
  return {
    label: weekly ? "7d" : "period",
    percent: clamp(percent),
    resetsAt: typeof end === "string" ? end : null,
  };
}

async function loadXai() {
  const token = await xaiToken();
  if (!token) return undefined;
  const payload = await fetchJson(XAI_URL, {
    Authorization: `Bearer ${token}`,
    "User-Agent": "herdr-subscription-usage",
    "x-grok-client-surface": "grok-build",
  });
  const window = xaiWindow(payload);
  return window ? [window] : undefined;
}

const PROVIDERS = [
  { id: "claude", label: "Claude", load: loadClaude },
  { id: "codex", label: "Codex", load: loadCodex },
  { id: "xai", label: "xAI", load: loadXai },
];

export default class SubscriptionUsage extends View {
  init(_props, cx) {
    if (props()?.detail) return;
    this.working = agents().filter((agent) => agent.status === "working").length;
    this.fetched = 0;
    this.gen = 0;
    this.refresh(cx, true);
    cx.timer.every(REFRESH_MS, (cx) => this.refresh(cx, true));
    cx.timer.every(2000, (cx) => {
      const working = agents().filter((agent) => agent.status === "working").length;
      if (working === this.working) return;
      this.working = working;
      this.refresh(cx, false);
    });
  }

  refresh(cx, force) {
    if (!force && Date.now() - this.fetched < MIN_FETCH_MS) return;
    this.fetched = Date.now();
    const gen = ++this.gen;
    const previous = shared(KEY)?.providers ?? [];
    cx.spawn(async (cx) => {
      const providers = [];
      for (const provider of PROVIDERS) {
        const prior = previous.find((row) => row.id === provider.id);
        try {
          const windows = await provider.load();
          if (windows) providers.push({ id: provider.id, label: provider.label, windows, stale: false });
          else if (prior?.windows?.length) providers.push({ ...prior, stale: true });
          else providers.push({ id: provider.id, label: provider.label, windows: [], stale: false });
        } catch {
          providers.push(prior?.windows?.length
            ? { ...prior, stale: true }
            : { id: provider.id, label: provider.label, windows: [], stale: false });
        }
      }
      if (this.gen !== gen) return;
      setShared(KEY, { at: Date.now(), providers });
      cx.notify();
    });
  }

  chip(t, window) {
    return h_flex().gap(4).items_center().flex_none()
      .child(div().text_color(t.dim).child(`${window.label}`))
      .child(div().text_color(tone(t, window.percent)).child(`${Math.round(window.percent)}%`));
  }

  group(t, provider) {
    const tip = provider.windows.map((window) => `${window.label} ${Math.round(window.percent)}% · resets ${formatReset(window.resetsAt)}`).join("\n");
    return h_flex().id(`usage-${provider.id}`).gap(8).items_center().flex_none().tooltip(tip || `${provider.label} n/a`)
      .child(div().text_color(t.muted).child(provider.label))
      .when(provider.windows.length === 0, (el) => el.child(div().text_color(t.dim).child("n/a")))
      .children(provider.windows.map((window) => this.chip(t, window)))
      .when(provider.stale, (el) => el.child(div().text_color(t.dim).child("stale")));
  }

  detail(t) {
    const providers = shared(KEY)?.providers ?? [];
    const rows = providers.flatMap((provider) => (provider.windows.length ? provider.windows : [{ label: "n/a", percent: null, resetsAt: null, empty: true }]).map((window) => ({ provider, window })));
    return v_flex().id("usage-detail").size_full().p(8).bg(t.popover).gap(2).overflow_y_scrollbar()
      .child(div().px(8).h(24).text_size(11).text_color(t.dim).child("Subscription usage"))
      .children(rows.map((row) => h_flex().h(28).px(8).gap(8).items_center().text_size(12.5)
        .child(div().w(64).text_color(t.muted).child(row.provider.label))
        .child(div().w(64).text_color(t.foreground).child(row.window.label))
        .child(div().w(48).text_color(row.window.percent == null ? t.dim : tone(t, row.window.percent))
          .child(row.window.percent == null ? "n/a" : `${Math.round(row.window.percent)}%`))
        .child(div().flex_1().text_color(t.dim).child(row.window.empty ? "" : `resets ${formatReset(row.window.resetsAt)}`))))
      .child(div().px(8).pt(6).text_size(11).text_color(t.dim).child("Esc closes · bar click refreshes"));
  }

  hint() {
    const mac = window()?.platform === "macos";
    const mod = { cmd: mac ? "⌘" : "Ctrl+", ctrl: mac ? "⌃" : "Ctrl+", shift: mac ? "⇧" : "Shift+", alt: mac ? "⌥" : "Alt+", option: mac ? "⌥" : "Alt+" };
    const binding = keys().find((key) => key.section === "global" && key.action === "app.palette");
    const parts = binding && binding.keys.endsWith("--") ? [...binding.keys.slice(0, -2).split("-"), "-"] : binding?.keys.split("-");
    const key = parts && parts.map((part) => mod[part.toLowerCase()] ?? part.toUpperCase()).join("");
    return key ? `${key}  commands` : "commands";
  }

  openDetail(cx) {
    this.refresh(cx, true);
    if (this.overlay) closeOverlay(this.overlay);
    this.overlay = openOverlay({ mod: "subscription-usage", kind: "popup", width: 420, height: 240, props: { detail: true } });
  }

  render(cx) {
    const t = theme();
    if (props()?.detail) return this.detail(t);
    const space = spaces().find((row) => row.active);
    const list = agents();
    const needs = list.filter((agent) => agent.status === "blocked").length;
    const providers = shared(KEY)?.providers ?? [];
    const label = (icon, text) => h_flex().gap(6).items_center().child(svg(`mods/workspace-chrome/${icon}.svg`).size(13)).child(text);
    return h_flex().id("subscription-usage").size_full().px(14).gap(16).items_center().bg(t.chrome)
      .border_t(1).border_color(t.border).text_size(11.8).text_color(t.muted)
      .child(label(space?.machine ? "server" : "monitor", space?.machine ?? "This computer"))
      .when(Boolean(space?.branch), (el) => el.child(label("branch", space.branch)))
      .child(h_flex().gap(6).items_center()
        .child(div().size(6).rounded(3).bg(t.dim))
        .child(`${list.length} agents`)
        .when(needs > 0, (el) => el.child(div().text_color(t.blocked).child(`· ${needs} needs you`))))
      .child(h_flex().id("usage-inline").gap(12).items_center().cursor_pointer()
        .on_click(() => this.openDetail(cx))
        .when(!providers.length, (el) => el.child(div().text_color(t.dim).child("usage …")))
        .children(providers.map((provider) => this.group(t, provider))))
      .child(div().flex_1())
      .child(div().id("palette").text_color(t.dim).on_click(() => run("app.palette")).child(this.hint()));
  }
}
