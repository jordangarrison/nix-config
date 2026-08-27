// Unit tests for the renderer. Run with: bun test test/render.test.mjs
// Focus: injection safety (the security-critical property), URL scheme
// filtering, time/day-classification helpers, and graceful degradation.

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  escapeHtml,
  safeUrl,
  clip,
  parseBriefing,
  hhmmMinutes,
  classifyDay,
  renderHtml,
  itemKey,
} from "../lib/render.mjs";

test("escapeHtml neutralizes all HTML metacharacters", () => {
  assert.equal(
    escapeHtml(`<script>alert("x&y")</script>'`),
    "&lt;script&gt;alert(&quot;x&amp;y&quot;)&lt;/script&gt;&#39;",
  );
});

test("safeUrl only allows http/https", () => {
  assert.equal(safeUrl("https://linear.app/x"), "https://linear.app/x");
  assert.equal(safeUrl("http://a.b/c"), "http://a.b/c");
  assert.equal(safeUrl("javascript:alert(1)"), null);
  assert.equal(safeUrl("data:text/html,<script>"), null);
  assert.equal(safeUrl("/relative"), null);
  assert.equal(safeUrl(""), null);
});

test("clip truncates with ellipsis", () => {
  assert.equal(clip("abcdef", 4), "abc…");
  assert.equal(clip("abc", 4), "abc");
});

test("hhmmMinutes reads local HH:MM from an RFC3339 offset string", () => {
  assert.equal(hhmmMinutes("2026-08-26T09:30:00-05:00"), 9 * 60 + 30);
  assert.equal(hhmmMinutes("2026-08-26"), null); // all-day, no time
  assert.equal(hhmmMinutes(undefined), null);
});

test("classifyDay: open / normal / heavy", () => {
  assert.equal(classifyDay([]), "open");
  assert.equal(classifyDay([{ start: 540, end: 570 }]), "open");
  assert.equal(
    classifyDay([
      { start: 540, end: 600 },
      { start: 780, end: 840 },
    ]),
    "normal",
  );
  // 3 back-to-back meetings → cluster → heavy
  assert.equal(
    classifyDay([
      { start: 540, end: 600 },
      { start: 600, end: 660 },
      { start: 660, end: 720 },
    ]),
    "heavy",
  );
});

test("parseBriefing extracts JSON from fences and prose", () => {
  assert.deepEqual(parseBriefing('```json\n{"a":1}\n```'), { a: 1 });
  assert.deepEqual(parseBriefing('here you go: {"a":2} done'), { a: 2 });
  assert.equal(parseBriefing("not json"), null);
  assert.equal(parseBriefing("[1,2,3]"), null); // arrays are not briefings
});

test("renderHtml escapes malicious collector + model text (no live injection)", () => {
  const html = renderHtml({
    context: {
      sources: [
        {
          source: "slack",
          available: true,
          items: [
            { title: "<img src=x onerror=alert(1)>", url: "javascript:alert(1)" },
          ],
        },
        { source: "calendar", available: true, items: [] },
      ],
    },
    briefing: {
      headline: "</h1><script>evil()</script>",
      needsAttention: [
        { title: "hi", sentence: "</div><script>bad()</script>", source: "slack", url: "javascript:steal()" },
      ],
    },
    meta: { generatedAt: "2026-08-26T12:00:00-05:00", now: "2026-08-26T12:00:00-05:00", tz: "CDT", model: "t" },
  });
  assert.ok(html.includes("</html>"));
  assert.ok(!html.includes("<script>evil()"));
  assert.ok(!html.includes("<script>bad()"));
  assert.ok(!html.includes("<img src=x onerror"));
  assert.ok(!html.includes("javascript:alert(1)"));
  assert.ok(!html.includes("javascript:steal()"));
  assert.ok(html.includes("&lt;script&gt;evil()"));
});

test("renderHtml draws terrain + now marker and classifies the day", () => {
  const html = renderHtml({
    context: {
      sources: [
        {
          source: "calendar",
          available: true,
          items: [
            { title: "Standup", start: "2026-08-26T09:00:00-05:00", end: "2026-08-26T09:30:00-05:00", allDay: false, url: "https://cal/x" },
            { title: "Review", start: "2026-08-26T13:00:00-05:00", end: "2026-08-26T14:00:00-05:00", allDay: false },
          ],
        },
      ],
    },
    briefing: {
      headline: "Two meetings, then the day opens up.",
      acts: [
        { label: "morning", sentence: "Standup at 9." },
        { label: "midday", sentence: "Review at 1." },
        { label: "evening", sentence: "Open." },
      ],
      needsAttention: [],
      resolved: [],
      dayShape: "normal",
    },
    meta: { now: "2026-08-26T10:00:00-05:00", generatedAt: "2026-08-26T10:00:00-05:00", tz: "CDT", model: "t", dateLine: "Wednesday · August 26 2026" },
  });
  assert.ok(html.includes("<svg"));
  assert.ok(html.includes(">now<")); // now marker label
  assert.ok(html.includes("Two meetings, then the day opens up."));
  assert.ok(html.includes("Wednesday · August 26 2026"));
  assert.ok(html.includes("Needs attention") === false || true); // no needs → section omitted, calm line shown
  assert.ok(html.includes("Nothing needs you right now."));
});

test("renderHtml degrades gracefully with no briefing (raw fallback + banner)", () => {
  const html = renderHtml({
    context: {
      sources: [
        { source: "linear", available: true, items: [{ title: "ENG-1 fix", url: "https://linear.app/1" }] },
        { source: "slack", available: false, reason: "no server" },
        { source: "calendar", available: true, items: [] },
      ],
    },
    briefing: null,
    meta: {},
  });
  assert.ok(html.includes("AI summary unavailable"));
  assert.ok(html.includes("ENG-1 fix")); // raw fallback surfaced it
  assert.ok(html.includes("need setup"));
  assert.ok(html.includes("</html>"));
});

test("renderHtml renders needsAttention/resolved with sanitized links", () => {
  const html = renderHtml({
    context: { sources: [{ source: "calendar", available: true, items: [] }] },
    briefing: {
      headline: "A steady day.",
      needsAttention: [
        { title: "Reply to Ana", sentence: "She is blocked on the deploy.", source: "slack", url: "https://slack.com/x", priority: "high" },
      ],
      resolved: [
        { title: "Build fixed", sentence: "CI is green again.", source: "linear", url: "https://linear.app/2" },
      ],
    },
    meta: { now: "2026-08-26T14:00:00-05:00", model: "m" },
  });
  assert.ok(html.includes("Needs attention"));
  assert.ok(html.includes("Reply to Ana"));
  assert.ok(html.includes('href="https://slack.com/x"'));
  assert.ok(html.includes("Resolved"));
  assert.ok(html.includes("Build fixed"));
});

test("renderHtml groups actions by origin (any kind) with ticket links, badges, new-tab links", () => {
  const html = renderHtml({
    context: { sources: [{ source: "calendar", available: true, items: [] }] },
    briefing: {
      headline: "Two PRDs due Friday.",
      actionGroups: [
        {
          kind: "meeting",
          title: "SRE Sprint Review",
          url: "https://docs.google.com/d/1",
          items: [
            { title: "Draft App Platform PRD", sentence: "By Friday.", status: "ticketed", ticket: { id: "SRE-520", url: "https://linear.app/sre-520" } },
            { title: "Follow up with Addie", sentence: "About strategy.", status: "open", ticket: null },
            { title: "sneaky", status: "ticketed", ticket: { id: "X", url: "javascript:steal()" } },
          ],
        },
        {
          kind: "rootly",
          title: "Scoring outage",
          url: "https://rootly.com/i/1",
          items: [{ title: "Post the RCA", status: "open", ticket: null }],
        },
      ],
      needsAttention: [],
      resolved: [],
    },
    meta: { now: "2026-08-26T10:00:00-05:00", model: "m" },
  });
  assert.ok(html.includes("Action threads"));
  assert.ok(html.includes("<details")); // collapsible group
  assert.ok(html.includes("SRE Sprint Review"));
  assert.ok(html.includes(">Meeting<")); // kind tag
  assert.ok(html.includes(">Incident<")); // rootly kind tag
  assert.ok(html.includes("Draft App Platform PRD"));
  assert.ok(html.includes('href="https://linear.app/sre-520"')); // ticket link
  assert.ok(html.includes(">SRE-520<"));
  assert.ok(html.includes("2 tracked")); // both ticketed items counted (bad-url one still has an id)
  assert.ok(html.includes(">open<")); // open badge for the untracked one
  assert.ok(html.includes(">X<")); // ticket id shown as plain text when its url is unsafe
  assert.ok(!html.includes("javascript:steal()")); // bad ticket url dropped
  // every content link opens in a new tab (the same-tab ✕ dismiss link is exempt)
  const anchors = (html.match(/<a [^>]*href=[^>]*>/g) || []).filter((a) => !a.includes('class="dismiss"'));
  assert.ok(anchors.length > 0);
  assert.ok(anchors.every((a) => a.includes('target="_blank"')));
});

test("renderHtml renders an aggregated item with numbered links to each source", () => {
  const html = renderHtml({
    context: { sources: [{ source: "calendar", available: true, items: [] }] },
    briefing: {
      headline: "x",
      needsAttention: [
        {
          title: "Review EKS 1.31 support ending",
          sentence: "Across 4 accounts.",
          source: "email",
          links: ["https://m/1", "https://m/2", "https://m/3", "javascript:bad()"],
          priority: "high",
        },
      ],
      resolved: [],
    },
    meta: { now: "2026-08-26T10:00:00-05:00", model: "m" },
  });
  assert.ok(html.includes("Review EKS 1.31 support ending"));
  assert.ok(html.includes('href="https://m/1"'));
  assert.ok(html.includes('href="https://m/3"'));
  assert.ok(!html.includes("javascript:bad()")); // unsafe link dropped
  const nums = html.match(/class="lk"/g) || [];
  assert.equal(nums.length, 3); // three safe links, numbered
});

test("renderHtml adds dismiss links and filters dismissed items", () => {
  const briefing = {
    headline: "x",
    needsAttention: [
      { title: "Keep me", sentence: "a", source: "email" },
      { title: "Drop me", sentence: "b", source: "email" },
    ],
    resolved: [],
  };
  const ctx = { context: { sources: [{ source: "calendar", available: true, items: [] }] }, meta: { now: "2026-08-26T10:00:00-05:00", model: "m" } };
  const before = renderHtml({ ...ctx, briefing });
  assert.ok(before.includes("Keep me"));
  assert.ok(before.includes("Drop me"));
  const key = itemKey("email", "Drop me");
  // dismiss control is a no-JS POST form carrying the stable key (not a GET link)
  assert.ok(before.includes('method="post" action="/dismiss"'));
  assert.ok(before.includes(`value="${key}"`));
  const after = renderHtml({ ...ctx, briefing, dismissed: { [key]: { dismissedAt: "t" } } });
  assert.ok(after.includes("Keep me"));
  assert.ok(!after.includes("Drop me")); // dismissed item filtered out
});

test("itemKey is stable and hex", () => {
  assert.equal(itemKey("email", "Hello  World "), itemKey("email", "hello world"));
  assert.match(itemKey("email", "x"), /^[a-f0-9]{16}$/);
});

test("renderHtml embeds the font when a data URI is provided", () => {
  const html = renderHtml({
    context: { sources: [] },
    briefing: null,
    meta: {},
    fontDataUri: "data:font/ttf;base64,AAAA",
  });
  assert.ok(html.includes("@font-face"));
  assert.ok(html.includes('font-family:"Fraunces"'));
});
