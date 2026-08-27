#!/usr/bin/env node
// render.mjs — deterministic, injection-safe renderer for the day dashboard.
//
// Aesthetic adapted from a personal "morning brief": a warm two-band page with
// a hand-drawn terrain of the day (elevation = meeting load), three "acts", and
// two calm lists — Needs attention / Resolved. Adapted for a dashboard that
// refreshes hourly: the terrain carries a clay "now" marker and the headline is
// written for the current moment, not just the start of the day.
//
// Non-negotiables kept from the original design:
//   * Everything gathered is DATA, never markup. Every interpolated string is
//     HTML-escaped; every URL is scheme-validated (http/https only). Embedded
//     instructions in gathered content are ignored — only our own prompt directs
//     the model, and the model's text is escaped here regardless.
//   * The terrain and day classification are computed deterministically from the
//     calendar collector (source of truth), not from the model.
//   * The AI briefing (headline / acts / lists) is best-effort. If it is missing
//     or invalid we still render a useful page and say so.
//
// Zero third-party dependencies (Node builtins only) so it runs under Nix.

import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";

// Stable per-item key so a dismissed item stays dismissed across renders. Based
// on source + normalized title: if the underlying thing materially changes
// (new title), the key changes and it may resurface — which is what we want.
export function itemKey(source, title) {
  const norm = String(title ?? "").toLowerCase().replace(/\s+/g, " ").trim();
  return createHash("sha1").update(`${String(source ?? "")}|${norm}`).digest("hex").slice(0, 16);
}

// Dismiss key namespace for a grouped action item: include the group's origin
// (url, else title) so identically-titled actions in two different groups don't
// collide and dismiss each other.
function groupSource(g) {
  return `group:${g.kind}|${g.url || g.title || ""}`;
}

// Small no-JS dismiss control. A POST form (not a GET link) so a cross-origin
// page can't silently dismiss/restore via a drive-by GET; the handler also
// checks Origin/Referer.
function dismissControl(key) {
  return ` <form class="dismiss" method="post" action="/dismiss"><input type="hidden" name="k" value="${escapeHtml(key)}"><button type="submit" title="Dismiss \u2014 already handled">\u2715</button></form>`;
}

const SOURCE_LABELS = {
  calendar: "Calendar",
  email: "Email",
  notes: "Meeting notes",
  slack: "Slack",
  linear: "Linear",
  github: "GitHub",
  rootly: "Rootly",
  confluence: "Confluence",
};

// How each kind of action-thread origin is labelled in a group header.
const KIND_LABELS = {
  meeting: "Meeting",
  notes: "Meeting",
  linear: "Linear",
  slack: "Slack thread",
  email: "Email",
  rootly: "Incident",
  incident: "Incident",
  github: "GitHub PR",
  confluence: "Confluence",
  support: "Support ticket",
  other: "",
};

const PRIORITY_RANK = { high: 0, medium: 1, low: 2 };

// Terrain window: 06:00–22:00 in minutes from local midnight.
const DAY_START = 6 * 60;
const DAY_END = 22 * 60;
const SVG_W = 840;
const SVG_H = 170;

// ── escaping / sanitizing ───────────────────────────────────────────────────
export function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function safeUrl(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (trimmed.length === 0 || trimmed.length > 2048) return null;
  try {
    const url = new URL(trimmed);
    if (url.protocol === "http:" || url.protocol === "https:") return url.href;
  } catch {
    /* not a URL */
  }
  return null;
}

export function clip(value, max = 400) {
  const s = String(value ?? "");
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

// ── time helpers (offset-safe: read HH:MM straight from the RFC3339 string,
// whose offset already encodes the user's local time) ───────────────────────
export function hhmmMinutes(iso) {
  if (typeof iso !== "string") return null;
  const m = iso.match(/T(\d{2}):(\d{2})/);
  if (!m) return null;
  return Number(m[1]) * 60 + Number(m[2]);
}

function fmtTime(min) {
  if (min == null) return "";
  let h = Math.floor(min / 60);
  const m = min % 60;
  const ap = h < 12 ? "AM" : "PM";
  h = h % 12;
  if (h === 0) h = 12;
  return m === 0 ? `${h} ${ap}` : `${h}:${String(m).padStart(2, "0")} ${ap}`;
}

// ── briefing parsing / normalization ────────────────────────────────────────
export function parseBriefing(raw) {
  if (!raw || typeof raw !== "string") return null;
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidates = [];
  if (fenced) candidates.push(fenced[1]);
  const first = raw.indexOf("{");
  const last = raw.lastIndexOf("}");
  if (first !== -1 && last > first) candidates.push(raw.slice(first, last + 1));
  candidates.push(raw);
  for (const c of candidates) {
    try {
      const obj = JSON.parse(c);
      if (obj && typeof obj === "object" && !Array.isArray(obj)) return obj;
    } catch {
      /* try next */
    }
  }
  return null;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

// Drop repeats by normalized title (the model sometimes lists the same item
// more than once, e.g. several near-identical notification emails).
function dedupeByTitle(items) {
  const seen = new Set();
  return items.filter((it) => {
    const key = (it.title || "").toLowerCase().replace(/\s+/g, " ").trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function normItem(x, { withPriority } = {}) {
  if (!x || typeof x !== "object") return null;
  const title = clip(x.title, 120);
  if (!title) return null;
  // links may hold several urls when the model merged related messages.
  const links = [...new Set(asArray(x.links).map(safeUrl).filter(Boolean))].slice(0, 10);
  const url = safeUrl(x.url) || links[0] || null;
  const out = {
    title,
    sentence: clip(x.sentence ?? x.detail, 240),
    source: typeof x.source === "string" ? x.source.toLowerCase() : "",
    url,
    links,
  };
  if (withPriority) out.priority = PRIORITY_RANK[x.priority] !== undefined ? x.priority : "medium";
  return out;
}

function normalizeBriefing(briefing) {
  if (!briefing || typeof briefing !== "object") return null;
  const headline = typeof briefing.headline === "string" ? clip(briefing.headline, 160) : "";
  const acts = asArray(briefing.acts)
    .filter((a) => a && typeof a === "object")
    .map((a) => ({ label: clip(a.label, 24), sentence: clip(a.sentence, 160) }))
    .slice(0, 3);
  const needsAttention = dedupeByTitle(
    asArray(briefing.needsAttention ?? briefing.focusNow)
      .map((x) => (typeof x === "string" ? { title: x } : x))
      .map((x) => normItem(x, { withPriority: true }))
      .filter(Boolean),
  )
    .sort((a, b) => PRIORITY_RANK[a.priority] - PRIORITY_RANK[b.priority])
    .slice(0, 10);
  const resolved = dedupeByTitle(
    asArray(briefing.resolved).map((x) => normItem(x)).filter(Boolean),
  ).slice(0, 8);
  const actionGroups = asArray(briefing.actionGroups ?? briefing.followupGroups)
    .filter((g) => g && typeof g === "object")
    .map((g) => ({
      kind: typeof g.kind === "string" && KIND_LABELS[g.kind.toLowerCase()] !== undefined ? g.kind.toLowerCase() : "other",
      title: clip(g.title ?? g.meeting, 100),
      url: safeUrl(g.url),
      items: dedupeByTitle(
        asArray(g.items)
          .map((it) => {
            if (!it || typeof it !== "object") return null;
            const title = clip(it.title, 120);
            if (!title) return null;
            const ticket =
              it.ticket && typeof it.ticket === "object" && it.ticket.id
                ? { id: clip(it.ticket.id, 24), url: safeUrl(it.ticket.url) }
                : null;
            return { title, sentence: clip(it.sentence, 240), status: ticket ? "ticketed" : "open", ticket };
          })
          .filter(Boolean),
      ).slice(0, 12),
    }))
    .filter((g) => g.title && g.items.length)
    .slice(0, 8);
  const dayShape = ["heavy", "normal", "open"].includes(briefing.dayShape) ? briefing.dayShape : null;
  if (
    !headline &&
    acts.length === 0 &&
    needsAttention.length === 0 &&
    resolved.length === 0 &&
    actionGroups.length === 0
  )
    return null;
  return { headline, acts, needsAttention, resolved, actionGroups, dayShape };
}

// ── calendar → timed events + classification + terrain ──────────────────────
function timedEvents(calendarSource) {
  if (!calendarSource || !calendarSource.available) return [];
  return asArray(calendarSource.items)
    .filter((it) => it && typeof it === "object" && !it.allDay)
    .map((it) => {
      const start = hhmmMinutes(it.start ?? it.when);
      let end = hhmmMinutes(it.end);
      if (start == null) return null;
      if (end == null) end = start + 30; // unknown → assume 30m
      else if (end <= start) end += 24 * 60; // spans midnight → next day
      return { start, end, title: clip(it.title, 80), url: safeUrl(it.url) };
    })
    .filter(Boolean)
    .sort((a, b) => a.start - b.start);
}

export function classifyDay(events) {
  const totalMin = events.reduce((s, e) => s + (e.end - e.start), 0);
  // cluster: 3+ events whose spans touch within 15m gaps
  let maxCluster = 0;
  let cur = 0;
  let prevEnd = -Infinity;
  for (const e of [...events].sort((a, b) => a.start - b.start)) {
    if (e.start - prevEnd <= 15) cur += 1;
    else cur = 1;
    prevEnd = Math.max(prevEnd, e.end);
    maxCluster = Math.max(maxCluster, cur);
  }
  if (totalMin >= 300 || maxCluster >= 3) return "heavy";
  if (totalMin <= 60 && events.length <= 1) return "open";
  return "normal";
}

function xOf(min) {
  const clamped = Math.max(DAY_START, Math.min(DAY_END, min));
  return ((clamped - DAY_START) / (DAY_END - DAY_START)) * SVG_W;
}

// Deterministic SVG terrain: one unbroken stroke whose elevation tracks meeting
// density, meeting dots on the line (past dimmed), and a clay "now" marker.
function buildTerrain(events, dayShape, nowMin) {
  const baseline = SVG_H - 30;
  const amp = dayShape === "heavy" ? 90 : dayShape === "open" ? 18 : 55;
  const step = 8;
  // load at a sample = weighted count of overlapping meetings, smoothed
  const loadAt = (min) => {
    let load = 0;
    for (const e of events) {
      const mid = (e.start + e.end) / 2;
      const half = Math.max(20, (e.end - e.start) / 2);
      const d = Math.abs(min - mid);
      if (d < half * 2.2) load += Math.max(0, 1 - d / (half * 2.2));
    }
    return load;
  };
  const maxLoad = Math.max(1, ...events.map((_, i, arr) => loadAt((arr[i].start + arr[i].end) / 2)));
  const pts = [];
  for (let x = 0; x <= SVG_W; x += step) {
    const min = DAY_START + (x / SVG_W) * (DAY_END - DAY_START);
    const y = baseline - (loadAt(min) / maxLoad) * amp;
    pts.push([x, Number(y.toFixed(1))]);
  }
  const yAt = (min) => {
    const x = xOf(min);
    const i = Math.min(pts.length - 1, Math.max(0, Math.round(x / step)));
    return pts[i][1];
  };
  const path = pts.map(([x, y], i) => `${i === 0 ? "M" : "L"}${x},${y}`).join(" ");

  const dots = events
    .map((e) => {
      const r = Math.max(6, Math.min(13, 6 + (e.end - e.start) / 30));
      const past = nowMin != null && e.end < nowMin;
      const color = past ? "#B4B3A8" : "#2E2C27";
      return `<circle cx="${xOf(e.start).toFixed(1)}" cy="${yAt(e.start)}" r="${r.toFixed(1)}" fill="${color}"/>`;
    })
    .join("");

  let nowMark = "";
  if (nowMin != null && nowMin >= DAY_START && nowMin <= DAY_END) {
    const x = xOf(nowMin).toFixed(1);
    nowMark = `<line x1="${x}" y1="8" x2="${x}" y2="${baseline + 6}" stroke="#C6613F" stroke-width="2" stroke-dasharray="2 4"/>` +
      `<text x="${x}" y="20" text-anchor="middle" fill="#C6613F" font-size="11" font-family="sans-serif">now</text>`;
  }

  return `<svg viewBox="0 0 ${SVG_W} ${SVG_H}" width="100%" preserveAspectRatio="xMidYMid meet" role="img" aria-label="the shape of the day">
    <path d="${path}" fill="none" stroke="#2E2C27" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
    ${dots}
    ${nowMark}
  </svg>`;
}

const ACTS = [
  { label: "Morning", start: DAY_START, end: 12 * 60 },
  { label: "Midday", start: 12 * 60, end: 17 * 60 },
  { label: "Evening", start: 17 * 60, end: DAY_END },
];

function actRange(a, events) {
  const inAct = events.filter((e) => e.start < a.end && e.end > a.start);
  if (inAct.length === 0) return fmtTime(a.start).replace(/ [AP]M/, "");
  const lo = Math.min(...inAct.map((e) => e.start));
  const hi = Math.max(...inAct.map((e) => e.end));
  const crossNoon = lo < 720 && hi >= 720;
  const loS = crossNoon ? fmtTime(lo) : fmtTime(lo).replace(/ [AP]M/, "");
  return `${loS} – ${fmtTime(hi)}`.toUpperCase();
}

// ── item rendering (source phrase is the only link) ─────────────────────────
function renderBriefItem(item, index) {
  const url = item.url;
  const titleText = escapeHtml(item.title);
  const title = url
    ? `<a class="ttl" href="${escapeHtml(url)}" target="_blank" rel="noreferrer noopener">${titleText}</a>`
    : `<span class="ttl">${titleText}</span>`;
  const srcLabel = SOURCE_LABELS[item.source] || item.source;
  const sentence = escapeHtml(item.sentence || "");
  // Quiet source phrase; for an aggregated item, add small numbered links to
  // each merged message so all the sources are one click away.
  let srcPhrase = srcLabel ? ` <span class="src">${escapeHtml(srcLabel)}</span>` : "";
  if (item.links && item.links.length > 1) {
    const nums = item.links
      .map((u, i) => `<a class="lk" href="${escapeHtml(u)}" target="_blank" rel="noreferrer noopener">${i + 1}</a>`)
      .join("");
    srcPhrase = ` <span class="src">${escapeHtml(srcLabel || "links")}</span> <span class="lks">${nums}</span>`;
  }
  const dismiss = dismissControl(itemKey(item.source, item.title));
  return `<li><span class="num">${index}</span><div><div class="line">${title}${dismiss}</div><div class="say">${sentence}${srcPhrase}</div></div></li>`;
}

function renderActionGroups(groups) {
  return groups
    .map((g) => {
      const tracked = g.items.filter((i) => i.status === "ticketed").length;
      const open = g.items.length - tracked;
      const origin = g.url
        ? `<a href="${escapeHtml(g.url)}" target="_blank" rel="noreferrer noopener">${escapeHtml(g.title)}</a>`
        : escapeHtml(g.title);
      const kindLabel = KIND_LABELS[g.kind] || "";
      const kindTag = kindLabel ? `<span class="kind">${escapeHtml(kindLabel)}</span> ` : "";
      const summary = `${kindTag}${origin} <span class="gcount">${g.items.length}${tracked ? ` · ${tracked} tracked` : ""}</span>`;
      const lis = g.items
        .map((it) => {
          let badge;
          if (it.status === "ticketed" && it.ticket) {
            badge = it.ticket.url
              ? `<a class="ticket" href="${escapeHtml(it.ticket.url)}" target="_blank" rel="noreferrer noopener">${escapeHtml(it.ticket.id)}</a>`
              : `<span class="ticket">${escapeHtml(it.ticket.id)}</span>`;
          } else {
            badge = `<span class="open">open</span>`;
          }
          const say = it.sentence ? `<div class="say">${escapeHtml(it.sentence)}</div>` : "";
          const dismiss = dismissControl(itemKey(groupSource(g), it.title));
          return `<li class="fu ${it.status}"><div class="line"><span class="ttl">${escapeHtml(it.title)}</span> ${badge}${dismiss}</div>${say}</li>`;
        })
        .join("");
      return `<details class="group"${open > 0 ? " open" : ""}><summary>${summary}</summary><ul class="items fus">${lis}</ul></details>`;
    })
    .join("");
}

function renderRawSource(source) {
  const label = escapeHtml(SOURCE_LABELS[source.source] || source.source);
  if (!source.available) {
    return `<div class="rawsrc off"><strong>${label}</strong> — ${escapeHtml(clip(source.reason || "not configured", 160))}</div>`;
  }
  const items = asArray(source.items).filter((it) => it && typeof it === "object");
  if (items.length === 0) return `<div class="rawsrc"><strong>${label}</strong> — clear</div>`;
  const lis = items
    .map((it) => {
      const url = safeUrl(it.url);
      const t = escapeHtml(clip(it.title, 140) || "(untitled)");
      const th = url ? `<a href="${escapeHtml(url)}" target="_blank" rel="noreferrer noopener">${t}</a>` : t;
      const extra = it.when ? ` <span class="src">${escapeHtml(clip(it.when, 40))}</span>` : "";
      return `<li>${th}${extra}</li>`;
    })
    .join("");
  return `<div class="rawsrc"><strong>${label}</strong><ul>${lis}</ul></div>`;
}

// ── fallbacks when the model briefing is missing ────────────────────────────
function fallbackNeedsAttention(sources) {
  const out = [];
  for (const s of sources) {
    if (!s.available) continue;
    if (s.source === "calendar") continue;
    for (const it of asArray(s.items)) {
      out.push({ title: clip(it.title, 120), sentence: clip(it.detail, 200), source: s.source, url: safeUrl(it.url), priority: "medium" });
      if (out.length >= 8) return out;
    }
  }
  return out;
}

function fallbackHeadline(dayShape) {
  if (dayShape === "heavy") return "A full day of meetings — the gaps are where the work happens.";
  if (dayShape === "open") return "The day is largely yours. Spend it on the thing that's been waiting.";
  return "Meetings bookend the day — the middle is yours.";
}

// ── page ────────────────────────────────────────────────────────────────────
export function renderHtml({ context, briefing, meta, fontDataUri, dismissed }) {
  const isDismissed = (source, title) =>
    dismissed && Object.prototype.hasOwnProperty.call(dismissed, itemKey(source, title));
  const sources = asArray(context?.sources);
  const calendar = sources.find((s) => s.source === "calendar");
  const events = timedEvents(calendar);
  const allDay = calendar && calendar.available
    ? asArray(calendar.items).filter((it) => it && it.allDay).map((it) => clip(it.title, 60))
    : [];

  const nowMin = hhmmMinutes(meta?.now || meta?.generatedAt);
  const brief = normalizeBriefing(briefing);
  // Day classification (and thus terrain amplitude) is a deterministic property
  // of the calendar, not the model — a briefing that mislabels a packed day as
  // "open" must not flatten the terrain. The model's dayShape is advisory only.
  const dayShape = classifyDay(events);

  const headline = escapeHtml((brief && brief.headline) || fallbackHeadline(dayShape));
  // Trust the model's curation when it ran at all (even an empty list means
  // "nothing needs you"). Only when there is no briefing do we surface raw
  // collector items so the page still says something useful.
  const needs = (brief ? brief.needsAttention : fallbackNeedsAttention(sources)).filter(
    (it) => !isDismissed(it.source, it.title),
  );
  const resolved = brief ? brief.resolved : [];

  const dateLine = escapeHtml(meta?.dateLine || meta?.generatedAt || "");
  const updated = escapeHtml(fmtTime(nowMin) || meta?.generatedAt || "");
  const model = escapeHtml(meta?.model || "");

  const terrain = buildTerrain(events, dayShape, nowMin);

  const actsHtml = ACTS.map((a, i) => {
    const range = escapeHtml(actRange(a, events));
    const sentence = escapeHtml((brief && brief.acts[i] && brief.acts[i].sentence) || "");
    const isNow = nowMin != null && nowMin >= a.start && nowMin < a.end;
    return `<div class="act${isNow ? " now" : ""}"><div class="range">${range}</div><div class="asay">${sentence}</div></div>`;
  }).join("");

  const allDayHtml = allDay.length
    ? `<div class="allday">All day: ${allDay.map((t) => escapeHtml(t)).join(" · ")}</div>`
    : "";

  // Filter dismissed follow-ups too, dropping any group left empty.
  const actionGroups = (brief ? brief.actionGroups : [])
    .map((g) => ({ ...g, items: g.items.filter((it) => !isDismissed(groupSource(g), it.title)) }))
    .filter((g) => g.items.length);
  const groupsHtml = actionGroups.length ? renderActionGroups(actionGroups) : "";

  const needsHtml = needs.length
    ? `<ol class="items">${needs.map((it, i) => renderBriefItem(it, i + 1)).join("")}</ol>`
    : "";
  const resolvedHtml = resolved.length
    ? `<ol class="items resolved">${resolved.map((it, i) => renderBriefItem(it, i + 1)).join("")}</ol>`
    : "";

  const allEmpty = needs.length === 0 && resolved.length === 0 && actionGroups.length === 0;
  const calmLine = allEmpty ? `<p class="calm">Nothing needs you right now.</p>` : "";

  const missing = sources.filter((s) => !s.available);
  const missingHtml = missing.length
    ? `<details class="setup"><summary>${missing.length} source(s) need setup</summary>${missing.map((s) => `<div class="rawsrc off"><strong>${escapeHtml(SOURCE_LABELS[s.source] || s.source)}</strong> — ${escapeHtml(clip(s.reason || "not configured", 160))}</div>`).join("")}</details>`
    : "";

  const rawHtml = `<details class="raw"><summary>Raw sources</summary>${sources.map(renderRawSource).join("")}</details>`;

  const briefingBanner = brief ? "" : `<p class="banner">AI summary unavailable this refresh — showing raw source data.</p>`;

  const fontFace = fontDataUri
    ? `@font-face{font-family:"Fraunces";src:url(${fontDataUri}) format("truetype");font-weight:600;font-display:swap;}`
    : "";
  const headlineFamily = fontDataUri ? '"Fraunces", Georgia, serif' : "Georgia, serif";

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta http-equiv="refresh" content="900">
<title>Day</title>
<style>
${fontFace}
:root{--bg:#FCFCFB;--wash:#F9F9F7;--ink:#2E2C27;--soft:#6B6A63;--grey:#B4B3A8;--hair:#E4E3DC;--line:#E1E1DF;--clay:#C6613F;--clayh:#AE5133;}
*{box-sizing:border-box;}
body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.6 -apple-system,"Segoe UI",Roboto,sans-serif;}
.band{padding:2.2rem 1.5rem;}
.top{background:var(--wash);border-bottom:1px solid var(--line);}
.wrap{max-width:860px;margin:0 auto;}
.date{color:var(--soft);font-size:.8rem;letter-spacing:.02em;margin-bottom:.4rem;}
h1{font-family:${headlineFamily};font-weight:600;font-size:40px;line-height:1.15;margin:0 0 1.4rem;color:var(--ink);}
.terrain{margin:0 0 .4rem;}
.acts{display:flex;gap:0;margin-top:.6rem;}
.act{flex:1;padding:0 1rem;}
.act + .act{border-left:1px solid var(--hair);}
.act .range{font-weight:700;font-size:.8rem;letter-spacing:.03em;margin-bottom:.25rem;}
.act.now .range{color:var(--clay);}
.act .asay{color:var(--soft);font-size:.9rem;}
.allday{margin-top:1rem;color:var(--soft);font-size:.85rem;}
h2{font-size:.72rem;text-transform:uppercase;letter-spacing:.09em;color:var(--soft);margin:0 0 .7rem;font-weight:600;}
.section + .section{margin-top:2rem;}
.items{list-style:none;margin:0;padding:0;}
.items li{display:flex;gap:.8rem;padding:.55rem 0;border-top:1px solid var(--hair);}
.items li:first-child{border-top:none;}
.num{color:var(--grey);font-variant-numeric:tabular-nums;font-size:.85rem;min-width:1.2rem;text-align:right;padding-top:.15rem;}
.line .ttl{font-weight:600;color:var(--ink);text-decoration:none;}
.line a.ttl:hover{text-decoration:underline;}
.say{color:var(--soft);font-size:.92rem;margin-top:.1rem;}
.src{color:var(--soft);text-decoration:underline;text-decoration-color:var(--grey);}
.lks{display:inline;}
.lk{display:inline-block;min-width:1.1em;text-align:center;font-size:.72rem;color:var(--soft);text-decoration:underline;text-decoration-color:var(--grey);margin:0 .1rem;}
form.dismiss{display:inline;margin:0;}
form.dismiss button{background:none;border:none;padding:0;margin-left:.4rem;cursor:pointer;color:var(--grey);font-size:.8rem;opacity:.5;font-family:inherit;line-height:1;}
form.dismiss button:hover{color:var(--off);opacity:1;}
.resolved .line .ttl{color:var(--soft);font-weight:500;}
.group{border-top:1px solid var(--hair);padding:.5rem 0;}
.group:first-of-type{border-top:none;}
.group > summary{cursor:pointer;font-weight:600;color:var(--ink);list-style:none;}
.group > summary::-webkit-details-marker{display:none;}
.group > summary::before{content:"\\25B8";color:var(--grey);margin-right:.5rem;font-size:.8rem;}
.group[open] > summary::before{content:"\\25BE";}
.group .kind{font-size:.68rem;text-transform:uppercase;letter-spacing:.06em;color:var(--soft);border:1px solid var(--hair);border-radius:.3rem;padding:.05rem .3rem;font-weight:600;}
.group .gcount{color:var(--grey);font-weight:400;font-size:.8rem;margin-left:.35rem;}
.fus{margin:.4rem 0 .4rem 1.4rem;}
.fu{display:block;padding:.4rem 0;border-top:1px solid var(--hair);}
.fu:first-child{border-top:none;}
.fu .ttl{font-weight:600;}
.fu.ticketed .ttl{color:var(--soft);font-weight:500;}
.ticket{font-size:.72rem;text-transform:uppercase;letter-spacing:.04em;color:var(--soft);text-decoration:underline;text-decoration-color:var(--grey);margin-left:.4rem;}
.open{font-size:.68rem;text-transform:uppercase;letter-spacing:.05em;color:var(--clay);margin-left:.4rem;}
.calm{color:var(--soft);}
.banner{color:var(--clay);font-size:.85rem;margin:0 0 1rem;}
.setup,.raw{margin-top:1.6rem;font-size:.82rem;color:var(--soft);}
.setup summary,.raw summary{cursor:pointer;color:var(--soft);}
.rawsrc{margin:.5rem 0;}
.rawsrc.off{opacity:.7;}
.rawsrc ul{margin:.2rem 0 0;padding-left:1.1rem;}
.rawsrc a{color:var(--soft);}
footer{max-width:860px;margin:0 auto;padding:1.5rem;color:var(--grey);font-size:.75rem;}
@media (max-width:640px){h1{font-size:30px;}.acts{flex-direction:column;}.act{padding:.6rem 0;}.act + .act{border-left:none;border-top:1px solid var(--hair);}}
</style>
</head>
<body>
<div class="band top"><div class="wrap">
  <div class="date">${dateLine}</div>
  <h1>${headline}</h1>
  <div class="terrain">${terrain}</div>
  <div class="acts">${actsHtml}</div>
  ${allDayHtml}
</div></div>
<div class="band"><div class="wrap">
  ${briefingBanner}
  ${calmLine}
  ${groupsHtml ? `<section class="section"><h2>Action threads</h2>${groupsHtml}</section>` : ""}
  ${needsHtml ? `<section class="section"><h2>Needs attention</h2>${needsHtml}</section>` : ""}
  ${resolvedHtml ? `<section class="section"><h2>Resolved</h2>${resolvedHtml}</section>` : ""}
  ${missingHtml}
  ${rawHtml}
</div></div>
<footer>Updated ${updated} · ${model} · private — refreshes hourly 06:00–21:00. ${escapeHtml(meta?.tz || "")}</footer>
</body>
</html>
`;
}

// ── CLI ─────────────────────────────────────────────────────────────────────
function parseJsonFile(path) {
  if (!path) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function loadFontDataUri(assetDir) {
  if (!assetDir) return null;
  try {
    const buf = readFileSync(`${assetDir}/headline.ttf`);
    if (buf.length > 0 && buf.length < 400_000) {
      return `data:font/ttf;base64,${buf.toString("base64")}`;
    }
  } catch {
    /* fall back to Georgia */
  }
  return null;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i]?.replace(/^--/, "");
    if (key) args[key] = argv[i + 1];
  }
  return args;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const context = parseJsonFile(args.context) || { sources: [] };
  let briefing = null;
  if (args.briefing) {
    let raw = "";
    try {
      raw = readFileSync(args.briefing, "utf8");
    } catch {
      /* none */
    }
    briefing = parseBriefing(raw);
  }
  const meta = parseJsonFile(args.meta) || {};
  const fontDataUri = loadFontDataUri(args["asset-dir"]);
  const dismissed = parseJsonFile(args.dismissed) || {};
  const html = renderHtml({ context, briefing, meta, fontDataUri, dismissed });
  if (!html.includes("</html>") || html.length < 400) {
    console.error("render: produced suspiciously small output; refusing");
    process.exit(1);
  }
  if (args.out) writeFileSync(args.out, html);
  else process.stdout.write(html);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
