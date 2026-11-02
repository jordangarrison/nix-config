// A work item groups spaces. Those spaces may live on different machines.
// Inside a group, spaces stay split by machine. Herdr keeps spaces flat;
// this mod only stores the grouping in shared("work.items").

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { spaces, machines, theme, shared, setShared, run, openOverlay, closeOverlay, props, layout, hc } from "herdr";

const KEY = "work.items";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;
const machineOf = (value) => value ?? null;
const sameMachine = (a, b) => machineOf(a) === machineOf(b);
const machineLabel = (machine) => machine ?? "This computer";

function nid() {
  return "wi-" + Math.random().toString(36).slice(2, 10);
}

function load() {
  const raw = shared(KEY);
  const items = Array.isArray(raw?.items)
    ? raw.items.filter((item) => item && typeof item.id === "string" && typeof item.name === "string")
      .map((item) => ({
        id: item.id,
        name: item.name,
        open: item.open !== false,
        spaces: Array.isArray(item.spaces) ? item.spaces.filter((id) => typeof id === "string") : [],
      }))
    : [];
  return {
    items,
    selected: typeof raw?.selected === "string" ? raw.selected : null,
    ungroupedOpen: raw?.ungroupedOpen !== false,
  };
}

function save(model) {
  const prev = shared(KEY);
  const next = {
    items: model.items,
    selected: model.selected,
    ungroupedOpen: model.ungroupedOpen !== false,
  };
  if (JSON.stringify(prev) !== JSON.stringify(next)) setShared(KEY, next);
  return next;
}

// A remote space id is "<machine>/<id>"; no prefix means this computer.
const hostOf = (spaceId) => (spaceId.includes("/") ? spaceId.split("/")[0] : null);

// Drop only spaces that are known to be gone. A machine that is not ready
// (offline or still loading) does not list its spaces, so keep them.
function prune(model, live) {
  let changed = false;
  const ids = new Set(live.map((space) => space.id));
  const ready = new Set(machines().filter((m) => m.layout === "ready").map((m) => m.name));
  const known = (id) => hostOf(id) === null || ready.has(hostOf(id));
  for (const item of model.items) {
    const kept = item.spaces.filter((id) => ids.has(id) || !known(id));
    if (kept.length !== item.spaces.length) {
      item.spaces = kept;
      changed = true;
    }
  }
  if (model.selected && !model.items.some((item) => item.id === model.selected)) {
    model.selected = null;
    changed = true;
  }
  return changed;
}

function ownerOf(model, spaceId) {
  return model.items.find((item) => item.spaces.includes(spaceId)) ?? null;
}

export default class WorkItems extends View {
  init(_props, cx) {
    this.seen = new Set(spaces().map((space) => space.id));
    this.claim = null;
    this.claimAt = 0;
    this.editing = null;
    this.draft = "";
    this.input = null;
    this.known = [];
    this.lastActive = spaces().find((space) => space.active)?.id ?? null;
    this.refreshMachines(cx);
    cx.timer.every(15000, (cx) => this.refreshMachines(cx));
    cx.timer.every(500, (cx) => {
      if (this.claim && Date.now() - this.claimAt > 20000) {
        this.claim = null;
        cx.notify();
      }
    });
  }

  refreshMachines(cx) {
    cx.spawn(async (cx) => {
      try {
        const result = await hc(["machine", "ls", "--json"]);
        if (result.code === 0) this.known = (JSON.parse(result.stdout).machines ?? []).filter((row) => !row.temporary);
      } catch {}
      cx.notify();
    });
  }

  machineNames() {
    const remote = new Set();
    for (const space of spaces()) if (space.machine) remote.add(space.machine);
    for (const row of machines()) if (row.name) remote.add(row.name);
    for (const row of this.known ?? []) if (row.name) remote.add(row.name);
    return [null, ...[...remote].sort()];
  }

  beginEdit(id, name) {
    this.editing = id;
    this.draft = name;
    this.input = InputState.new({ value: name });
    if (name) this.input.set_selected_range({ start: 0, end: name.length });
    this.input.on("change", (_e, cx) => {
      this.draft = this.input.value();
      cx.notify();
    });
    this.input.on("submit", () => this.commitEdit());
    this.input.focus();
  }

  commitEdit() {
    const name = this.draft.trim();
    const model = load();
    if (this.editing === "new") {
      if (name) {
        const item = { id: nid(), name, open: true, spaces: [] };
        model.items.push(item);
        model.selected = item.id;
      }
    } else if (name) {
      const item = model.items.find((row) => row.id === this.editing);
      if (item) item.name = name;
    }
    save(model);
    this.cancelEdit();
  }

  cancelEdit() {
    this.editing = null;
    this.input = null;
  }

  claimNew(model) {
    const live = spaces();
    const ids = new Set(live.map((space) => space.id));
    if (this.claim) {
      const item = model.items.find((row) => row.id === this.claim.id);
      for (const space of live) {
        if (this.seen.has(space.id) || !item || !sameMachine(space.machine, this.claim.machine)) continue;
        for (const row of model.items) row.spaces = row.spaces.filter((id) => id !== space.id);
        if (!item.spaces.includes(space.id)) item.spaces.push(space.id);
        model.selected = item.id;
        this.claim = null;
        break;
      }
    }
    this.seen = ids;
  }

  followActive(model) {
    const active = spaces().find((space) => space.active);
    if (!active || active.id === this.lastActive) return;
    this.lastActive = active.id;
    const owner = ownerOf(model, active.id);
    if (!owner) return;
    owner.open = true;
    model.selected = owner.id;
  }

  selectItem(item) {
    const model = load();
    const row = model.items.find((candidate) => candidate.id === item.id);
    if (!row) return;
    row.open = true;
    model.selected = row.id;
    save(model);
    const live = spaces();
    if (live.some((space) => space.active && row.spaces.includes(space.id))) return;
    const first = live.find((space) => row.spaces.includes(space.id));
    if (first) {
      this.lastActive = first.id;
      run("space.select", { id: first.id });
    }
  }

  toggleItem(item) {
    const model = load();
    const row = model.items.find((candidate) => candidate.id === item.id);
    if (!row) return;
    row.open = !row.open;
    save(model);
  }

  addSpace(item) {
    const names = this.machineNames();
    if (names.length < 2) {
      this.newSpace(item, null);
      return;
    }
    openOverlay({
      mod: "work-items",
      kind: "popup",
      width: 220,
      height: 160,
      props: { menu: "new-space", item: item.id },
    });
  }

  newSpace(item, machine) {
    this.claim = { id: item.id, machine: machineOf(machine) };
    this.claimAt = Date.now();
    const model = load();
    const row = model.items.find((candidate) => candidate.id === item.id);
    if (row) {
      row.open = true;
      model.selected = row.id;
      save(model);
    }
    run("space.new", machine ? { machine } : {});
  }

  moveSpace(spaceId, itemId) {
    const model = load();
    for (const item of model.items) item.spaces = item.spaces.filter((id) => id !== spaceId);
    if (itemId) {
      const item = model.items.find((row) => row.id === itemId);
      if (item) {
        item.spaces.push(spaceId);
        item.open = true;
        model.selected = item.id;
      }
    }
    save(model);
  }

  removeItem(id) {
    const model = load();
    model.items = model.items.filter((item) => item.id !== id);
    if (model.selected === id) model.selected = null;
    save(model);
  }

  spaceMenu(spaceId) {
    openOverlay({
      mod: "work-items",
      kind: "popup",
      width: 220,
      height: 280,
      props: { menu: "space", space: spaceId },
    });
  }

  itemMenu(itemId) {
    openOverlay({
      mod: "work-items",
      kind: "popup",
      width: 180,
      height: 96,
      props: { menu: "item", item: itemId },
    });
  }

  menuRow(id, label, action, t) {
    return h_flex().id(id).h(32).px(10).items_center().rounded(6).text_size(12.5).text_color(t.foreground)
      .cursor_pointer().hover((s) => s.bg(t.hover)).on_click(action).child(label);
  }

  menu(p, t) {
    const model = load();
    const close = () => closeOverlay(p.overlay);
    if (p.menu === "item") {
      return v_flex().id("work-item-menu").size_full().p(6).bg(t.popover).gap(2)
        .child(this.menuRow("work-rename", "Rename", () => {
          setShared("work.edit", p.item);
          close();
        }, t))
        .child(this.menuRow("work-delete", "Delete group", () => {
          this.removeItem(p.item);
          close();
        }, t));
    }
    if (p.menu === "new-space") {
      const item = model.items.find((row) => row.id === p.item);
      return v_flex().id("work-new-space").size_full().p(6).bg(t.popover).gap(2)
        .child(div().px(10).h(24).text_size(11).text_color(t.dim).child("New space on"))
        .children(this.machineNames().map((machine) => this.menuRow(`new-on-${machine ?? "local"}`, machineLabel(machine), () => {
          if (item) this.newSpace(item, machine);
          close();
        }, t)));
    }
    const current = ownerOf(model, p.space);
    const targets = model.items.filter((item) => item.id !== current?.id);
    return v_flex().id("work-space-menu").size_full().p(6).bg(t.popover).gap(2).overflow_y_scrollbar()
      .child(div().px(10).h(24).flex_none().text_size(11).text_color(t.dim).child("Move to"))
      .children(targets.map((item) => this.menuRow(`move-${item.id}`, item.name, () => {
        this.moveSpace(p.space, item.id);
        close();
      }, t)))
      .when(!targets.length, (el) => el.child(div().px(10).h(28).text_size(12).text_color(t.dim).child("No other groups")))
      .when(Boolean(current), (el) => el.child(this.menuRow("move-out", "Remove from group", () => {
        this.moveSpace(p.space, null);
        close();
      }, t)));
  }

  spaceRow(space, t, pad) {
    return h_flex().id(`work-space-${space.id}`).h(28).flex_none().px(8).ml(pad).gap(8).items_center().rounded(7)
      .when(space.active, (el) => el.bg(t.selected))
      .when(!space.active, (el) => el.hover((s) => s.bg(t.hover)))
      .cursor_pointer()
      .on_click(() => {
        this.lastActive = space.id;
        const model = load();
        const owner = ownerOf(model, space.id);
        if (owner) {
          owner.open = true;
          model.selected = owner.id;
          save(model);
        }
        run("space.select", { id: space.id });
      })
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        this.spaceMenu(space.id);
      })
      .child(div().size(7).rounded(4).flex_none().bg(space.status === "blocked" || space.status === "done" ? t.accent : t.dim))
      .child(div().flex_1().min_w(0).truncate().text_size(12.5).text_color(t.foreground).child(space.name))
      .when(Boolean(space.branch), (el) => el.child(div().flex_none().max_w(90).truncate().text_size(11).text_color(t.dim).child(space.branch)));
  }

  machineRow(machine, t, scope) {
    return h_flex().id(`work-machine-${scope}-${machine ?? "local"}`).h(22).flex_none().ml(16).px(4).gap(6).items_center()
      .text_size(11).text_color(t.dim)
      .child(svg(`mods/workspace-chrome/${machine ? "server" : "monitor"}.svg`).size(12).flex_none())
      .child(machineLabel(machine));
  }

  rowsFor(spacesInGroup, t, showMachines, pad, scope) {
    if (!spacesInGroup.length) return [];
    if (!showMachines) return spacesInGroup.map((space) => this.spaceRow(space, t, pad));
    return this.machineNames().filter((machine) => spacesInGroup.some((space) => sameMachine(space.machine, machine)))
      .flatMap((machine) => [
        this.machineRow(machine, t, scope),
        ...spacesInGroup.filter((space) => sameMachine(space.machine, machine)).map((space) => this.spaceRow(space, t, pad + 12)),
      ]);
  }

  itemHeader(item, t, count) {
    const on = load().selected === item.id;
    return h_flex().id(`work-item-${item.id}`).h(32).flex_none().px(6).gap(6).items_center().rounded(8)
      .when(on, (el) => el.bg(t.selected))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .cursor_pointer()
      .on_click(() => this.selectItem(item))
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        this.itemMenu(item.id);
      })
      .child(div().size(18).flex_none().flex().items_center().justify_center()
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => {
          cx.stop_propagation();
          this.toggleItem(item);
        })
        .child(svg(`mods/workspace-chrome/chevron-${item.open ? "down" : "right"}.svg`).size(12).text_color(t.dim)))
      .child(div().flex_1().min_w(0).truncate().text_size(13).font_medium().text_color(t.foreground).child(item.name))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(String(count)))
      .child(div().id(`work-add-space-${item.id}`).size(22).flex_none().flex().items_center().justify_center().rounded(5)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => {
          cx.stop_propagation();
          this.addSpace(item);
        })
        .child(svg("mods/workspace-chrome/plus.svg").size(12).text_color(t.dim)));
  }

  editor(t) {
    const cancel = (event, cx) => {
      if (event.key === "escape") {
        this.cancelEdit();
        cx.stop_propagation();
        cx.notify();
      }
    };
    return v_flex().id("work-editor").px(8).pb(6).flex_none()
      .child(Input.new(this.input).h(32).px(8).rounded(8).border_1().border_color(t.accent).bg(t.background)
        .text_size(12.5).text_color(t.foreground).on_key_down(cancel))
      .child(div().pt(4).text_size(11).text_color(t.dim).child("Enter saves · Esc cancels"));
  }

  sidebar(t) {
    const model = load();
    const live = spaces();
    if (prune(model, live)) save(model);
    this.claimNew(model);
    this.followActive(model);
    save(model);

    const edit = shared("work.edit");
    if (edit && this.editing !== edit) {
      const item = model.items.find((row) => row.id === edit);
      if (item) this.beginEdit(item.id, item.name);
      setShared("work.edit", null);
    }

    const showMachines = this.machineNames().length > 1;
    const byId = Object.fromEntries(live.map((space) => [space.id, space]));
    const grouped = new Set(model.items.flatMap((item) => item.spaces));
    const ungrouped = live.filter((space) => !grouped.has(space.id));
    const rows = [];
    if (!model.items.length && this.editing !== "new") {
      rows.push(div().px(6).pt(8).text_size(12).text_color(t.dim).child("Add a work item, then put spaces inside it."));
    }
    for (const item of model.items) {
      const members = item.spaces.map((id) => byId[id]).filter(Boolean);
      rows.push(this.itemHeader(item, t, members.length));
      if (this.editing === item.id) rows.push(this.editor(t));
      if (!item.open) continue;
      rows.push(...this.rowsFor(members, t, showMachines, 6, item.id));
      if (!members.length) {
        rows.push(h_flex().id(`work-empty-${item.id}`).h(28).ml(18).px(8).items_center().rounded(7)
          .text_size(12).text_color(t.dim).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click(() => this.addSpace(item))
          .child("New space"));
      }
    }
    if (ungrouped.length) {
      rows.push(h_flex().id("work-ungrouped").h(26).px(6).mt(8).items_center().gap(6).cursor_pointer()
        .on_click(() => {
          const next = load();
          next.ungroupedOpen = !next.ungroupedOpen;
          save(next);
        })
        .child(svg(`mods/workspace-chrome/chevron-${model.ungroupedOpen ? "down" : "right"}.svg`).size(12).text_color(t.dim))
        .child(div().text_size(11).text_color(t.dim).child(`Ungrouped · ${ungrouped.length}`)));
      if (model.ungroupedOpen) rows.push(...this.rowsFor(ungrouped, t, showMachines, 0, "ungrouped"));
    }

    return v_flex().id("work-items").size_full().min_h(0).bg(t.chrome).text_size(13).text_color(t.foreground)
      .on_key_down((event, cx) => {
        if (event.key === "escape" && this.editing) {
          this.cancelEdit();
          cx.stop_propagation();
          cx.notify();
        }
      })
      .child(h_flex().h(31).pl(14).pr(8).flex_none().items_center().justify_between()
        .child(div().text_size(11.5).text_color(t.dim).child("Work"))
        .child(div().id("work-new").size(26).flex().items_center().justify_center().rounded(6)
          .hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => {
            this.beginEdit("new", "");
            cx.notify();
          })
          .child(svg("mods/workspace-chrome/plus.svg").size(14))))
      .when(this.editing === "new", (el) => el.child(this.editor(t)))
      .child(v_flex().flex_1().min_h(0).px(8).pb(12).gap(2).overflow_y_scrollbar().mode("always").children(rows));
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    if (p.menu) return this.menu(p, t);
    if (narrow()) {
      const model = load();
      return v_flex().size_full().bg(t.chrome).pt(8).gap(4).items_center()
        .children(model.items.map((item) => div().id(`work-rail-${item.id}`).size(28).rounded(7)
          .flex().items_center().justify_center().text_size(11).font_bold()
          .text_color(model.selected === item.id ? t.foreground : t.dim)
          .bg(model.selected === item.id ? t.selected : t.chrome)
          .cursor_pointer()
          .on_click(() => this.selectItem(item))
          .child((item.name[0] ?? "?").toUpperCase())));
    }
    return this.sidebar(t);
  }
}
