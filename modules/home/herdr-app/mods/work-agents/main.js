// Agents for the work-item layout, in the shape of the T3 Code sidebar.
// Ready stays open: an agent that needs you, or that you have used in the last
// three days. Working is collapsed while an agent is in flight. Settled is
// collapsed: untouched for three days, or settled by hand when the work is done.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { agents, spaces, terminals, theme, run, setAgentOrder, layout, openOverlay, closeOverlay, props, setShared, shared } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;
const QUIET = 3 * 24 * 60 * 60 * 1000;

function overrides() {
  try {
    return JSON.parse(localStorage.getItem("work.agents.override") ?? "{}");
  } catch {
    return {};
  }
}

function setOverride(address, value) {
  const next = overrides();
  if (value) next[address] = value;
  else delete next[address];
  localStorage.setItem("work.agents.override", JSON.stringify(next));
  setShared("work.agents.tick", Date.now());
}

function duration(ms) {
  const s = Math.floor(ms / 1000);
  if (s < 60) return `${Math.max(s, 1)}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

function mark(program, size, color) {
  if (!program?.icon) return null;
  return program.tint ? svg(program.icon).size(size).flex_none().text_color(color) : image(program.icon).w(size).h(size).flex_none();
}

export default class WorkAgents extends View {
  init(_props, cx) {
    this.changed = {};
    this.open = new Set();
    try {
      this.changed = JSON.parse(localStorage.getItem("work.agents.changed") ?? "{}");
      this.open = new Set(JSON.parse(localStorage.getItem("work.agents.open") ?? "[]"));
    } catch {}
    cx.timer.every(30000, (cx) => cx.notify());
  }

  track(list, now) {
    let dirty = false;
    for (const agent of list) {
      if (this.changed[agent.address]?.s === agent.status) continue;
      this.changed[agent.address] = { s: agent.status, at: now };
      dirty = true;
    }
    if (!dirty) return;
    const live = new Set(list.map((agent) => agent.address));
    for (const [key, value] of Object.entries(this.changed)) {
      if (!live.has(key) && now - value.at > 30 * 86400000) delete this.changed[key];
    }
    localStorage.setItem("work.agents.changed", JSON.stringify(this.changed));
  }

  bucket(agent, now) {
    if (agent.status === "blocked" || this.needsChild(agent)) return "ready";
    if (agent.status === "working") return "working";
    const choice = overrides()[agent.address];
    if (choice === "settled") return "settled";
    if (choice === "active") return "ready";
    const touched = this.changed[agent.address]?.at ?? now;
    if (agent.status === "idle" && now - touched >= QUIET) return "settled";
    return "ready";
  }

  needsChild(agent) {
    return terminals().some((row) => row.parent === agent.address && row.state === "live" && (row.status === "blocked" || row.status === "error"));
  }

  toggle(id) {
    this.open.has(id) ? this.open.delete(id) : this.open.add(id);
    localStorage.setItem("work.agents.open", JSON.stringify([...this.open]));
  }

  touch(agent) {
    this.changed[agent.address] = { s: agent.status, at: Date.now() };
    localStorage.setItem("work.agents.changed", JSON.stringify(this.changed));
  }

  openAgent(agent) {
    this.touch(agent);
    if (agent.pane) run("pane.focus", { pane: agent.pane });
    else run("agent.focus", { terminal: agent.address });
  }

  menuFor(agent, settled) {
    openOverlay({
      mod: "work-agents",
      kind: "popup",
      width: 180,
      height: 72,
      props: { menu: true, address: agent.address, settled },
    });
  }

  row(agent, t, now, settled = false) {
    const space = spaces().find((row) => row.id === agent.space);
    const title = agent.tab_name && !/^\d+$/.test(agent.tab_name) ? agent.tab_name : agent.title || agent.program?.name || agent.space_name;
    const when = this.changed[agent.address]?.at;
    const machine = agent.address.includes("/") ? agent.address.split("/")[0] : null;
    const pic = mark(agent.program, 16, t.foreground);
    return v_flex().id(`wa-${agent.address}`).px(8).py(6).gap(2).flex_none().rounded(8)
      .when(agent.focused, (el) => el.bg(t.selected))
      .when(!agent.focused, (el) => el.hover((s) => s.bg(t.hover)))
      .cursor_pointer()
      .on_click(() => this.openAgent(agent))
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        this.menuFor(agent, settled);
      })
      .child(h_flex().gap(6).items_center()
        .when(Boolean(pic), (el) => el.child(pic))
        .when(!pic, (el) => el.child(div().size(16).rounded(4).flex_none().bg(t.raised).flex().items_center().justify_center()
          .text_size(9).font_bold().text_color(t.dim).child((agent.space_name || "?").slice(0, 2).toUpperCase())))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(machine ? `${agent.space_name} · ${machine}` : agent.space_name || "Agent"))
        .when(Boolean(when), (el) => el.child(div().flex_none().text_size(11).text_color(t.dim).child(duration(now - when)))))
      .child(div().truncate().text_size(13).font_medium().text_color(t.foreground).child(title))
      .when(Boolean(space?.branch), (el) => el.child(div().truncate().text_size(11).text_color(t.dim).child(space.branch)));
  }

  shelf(id, label, count, t) {
    const open = this.open.has(id);
    return h_flex().id(`wa-shelf-${id}`).h(32).px(8).flex_none().items_center().gap(8).rounded(8)
      .cursor_pointer().hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => {
        this.toggle(id);
        cx.notify();
      })
      .child(div().flex_1().text_size(13).text_color(t.foreground).child(label))
      .child(div().text_size(12).text_color(t.dim).child(String(count)))
      .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(12).text_color(t.dim));
  }

  menu(p, t) {
    const close = () => closeOverlay(p.overlay);
    const label = p.settled ? "Unsettle" : "Settle";
    return v_flex().id("wa-menu").size_full().p(6).bg(t.popover)
      .child(h_flex().id("wa-settle").h(32).px(10).items_center().rounded(6).text_size(12.5).text_color(t.foreground)
        .cursor_pointer().hover((s) => s.bg(t.hover))
        .on_click(() => {
          setOverride(p.address, p.settled ? "active" : "settled");
          close();
        })
        .child(label));
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    if (p.menu) return this.menu(p, t);
    shared("work.agents.tick");
    const now = Date.now();
    const list = agents();
    this.track(list, now);
    const ready = [];
    const working = [];
    const settled = [];
    for (const agent of list) {
      const bucket = this.bucket(agent, now);
      if (bucket === "working") working.push(agent);
      else if (bucket === "settled") settled.push(agent);
      else ready.push(agent);
    }
    const order = [...ready, ...working, ...settled];
    setAgentOrder(order.map((agent) => agent.address));

    if (narrow()) {
      return v_flex().size_full().bg(t.chrome).pt(8).gap(6).items_center()
        .child(div().id("wa-rail-ready").size(22).rounded(6).flex().items_center().justify_center()
          .text_size(11).font_bold().text_color(ready.length ? t.foreground : t.dim)
          .bg(ready.length ? t.selected : t.chrome).child(String(ready.length)));
    }

    const rows = [];
    if (ready.length) {
      rows.push(h_flex().id("wa-ready").h(32).px(8).flex_none().items_center().gap(8)
        .child(div().flex_1().text_size(13).text_color(t.foreground).child("Ready"))
        .child(div().text_size(12).text_color(t.dim).child(String(ready.length))));
      rows.push(...ready.map((agent) => this.row(agent, t, now)));
    }
    if (working.length) {
      rows.push(this.shelf("working", "Working", working.length, t));
      if (this.open.has("working")) rows.push(...working.map((agent) => this.row(agent, t, now)));
    }
    if (settled.length) {
      rows.push(this.shelf("settled", "Settled", settled.length, t));
      if (this.open.has("settled")) rows.push(...settled.map((agent) => this.row(agent, t, now, true)));
    }

    return v_flex().id("work-agents").size_full().min_h(0).bg(t.chrome).border_t(1).border_color(t.border).text_color(t.foreground)
      .child(h_flex().h(31).pl(14).pr(8).flex_none().items_center()
        .child(div().text_size(11.5).text_color(t.dim).child("Agents")))
      .when(!list.length, (el) => el.child(div().px(14).text_size(12).text_color(t.dim).child("Agents show up here when they report status.")))
      .child(v_flex().flex_1().min_h(0).px(6).pb(8).gap(2).overflow_y_scrollbar().mode("always").children(rows));
  }
}
