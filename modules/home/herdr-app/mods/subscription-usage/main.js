// Claude, Codex, and xAI subscription windows.
// Claude and Codex share jagpi's collector with the board. Only xAI is fetched locally.

import { View, div, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, checking, props, agents, spaces, run, window, keys, shared, setShared, openOverlay, closeOverlay, home, exec } from "herdr";
import * as fs from "fs/promises";

const KEY = "subscription.usage.jagpi";
const USAGE_POLL_MS = 60 * 1000;
const USAGE_STALE_AFTER_MS = 15 * 60 * 1000;
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

function formatReset(at, measuredAt) {
  const ms = typeof at === "number" ? at : typeof at === "string" ? Date.parse(at) : NaN;
  if (!Number.isFinite(ms)) return "unknown";
  if (Number.isFinite(measuredAt) && measuredAt < ms && ms <= Date.now()) return "passed since measurement";
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

const JAGPI_PROVIDERS = [
  { provider: "claude", id: "claude", label: "Claude" },
  { provider: "openai", id: "codex", label: "Codex" },
];

async function loadJagpi(machine, allowlist) {
  const reply = await exec("jagpi", ["--instance", "default", "usage", "--json"], { on: machine, timeout: 30000 });
  if (reply.code !== 0) throw new Error("Usage unavailable");
  const subscriptions = JSON.parse(reply.stdout)?.result?.subscriptions;
  if (!Array.isArray(subscriptions)) throw new Error("Invalid usage result");
  return JAGPI_PROVIDERS.flatMap(({ provider, id, label }) => {
    const cards = subscriptions.filter((row) => row?.provider === provider
      && (!Array.isArray(allowlist) || allowlist.includes(row.modelProvider)));
    if (!cards.length) return [{ id, label, windows: [] }];
    return cards.map((card, index) => {
      const measuredAt = finite(card.measuredAt);
      const windows = measuredAt === undefined ? [] : (card.windows ?? []).flatMap((window) => {
        const used = finite(window?.used);
        const limit = finite(window?.limit);
        if (used === undefined || limit === undefined || limit <= 0 || used < 0 || used > limit
          || typeof window.label !== "string") return [];
        return [{ label: window.label, percent: used / limit * 100, resetsAt: finite(window.resetAt) ?? null }];
      });
      return {
        id: cards.length > 1 ? `${id}-${index}` : id,
        label: cards.length > 1 ? `${label} · ${card.account}` : label,
        windows,
        measuredAt,
      };
    });
  });
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

export default class SubscriptionUsage extends View {
  init(_props, cx) {
    if (checking() || props()?.detail) return;
    this.gen = 0;
    this.refresh(cx);
    cx.timer.every(USAGE_POLL_MS, (cx) => this.refresh(cx));
  }

  refresh(cx) {
    const gen = ++this.gen;
    const { machine = null, providers: allowlist } = props() ?? {};
    const source = JSON.stringify([machine, allowlist]);
    const previous = shared(KEY);
    cx.spawn(async (cx) => {
      // On transport failure retain measurements only from the same source and allowlist.
      // A successful empty result replaces them (for example, when an account is removed).
      const [jagpi, xai] = await Promise.all([
        loadJagpi(machine, allowlist).catch(() => previous?.source === source
          ? previous.providers.filter((row) => row.id !== "xai")
          : JAGPI_PROVIDERS.map(({ id, label }) => ({ id, label, windows: [] }))),
        loadXai().then((windows) => windows && { id: "xai", label: "xAI", windows, measuredAt: Date.now() })
          .catch(() => undefined),
      ]);
      const local = xai ?? previous?.providers?.find((row) => row.id === "xai") ?? { id: "xai", label: "xAI", windows: [] };
      if (this.gen !== gen) return;
      setShared(KEY, { at: Date.now(), source, providers: [...jagpi, local] });
      cx.notify();
    });
  }

  chip(t, window) {
    return h_flex().gap(4).items_center().flex_none()
      .child(div().text_color(t.dim).child(`${window.label}`))
      .child(div().text_color(tone(t, window.percent)).child(`${Math.round(window.percent)}%`));
  }

  group(t, provider) {
    const tip = provider.windows.map((window) => `${window.label} ${Math.round(window.percent)}% · resets: ${formatReset(window.resetsAt, provider.measuredAt)}`).join("\n");
    return h_flex().id(`usage-${provider.id}`).gap(8).items_center().flex_none().tooltip(tip || `${provider.label} n/a`)
      .child(div().text_color(t.muted).child(provider.label))
      .when(provider.windows.length === 0, (el) => el.child(div().text_color(t.dim).child("n/a")))
      .children(provider.windows.map((window) => this.chip(t, window)))
      .when(Number.isFinite(provider.measuredAt) && Date.now() - provider.measuredAt > USAGE_STALE_AFTER_MS, (el) => el.child(div().text_color(t.dim).child("stale")));
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
        .child(div().flex_1().text_color(t.dim).child(row.window.empty ? "" : `resets: ${formatReset(row.window.resetsAt, row.provider.measuredAt)}`))))
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
    this.refresh(cx);
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
