// Work items sidebar: machine -> items -> spaces.
//
// The rules are the MODEL section below. The rest does the effects and draws:
// - Lists: each connected machine's item list, read from LIST_FILE on
//   that machine and written there atomically.
// - Labels: `work.item=<id>` on a space's terminals, set with hc() on the
//   machine that hosts the space. New tabs and splits get the label copied.
// - View: same-named items across machines show as one row, computed on each
//   render. An offline machine's items are absent.
//
// The app stores no item data. localStorage keeps view state only: folded
// rows and the ungrouped fold. Menus are overlay copies of this mod: they get
// what they show in props and post actions in shared("work.request").

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import {
  spaces, panes, terminals, machines, theme, shared, setShared, run, openOverlay, closeOverlay, props, layout,
  hc, exec, readTextFile, home, notify,
} from "herdr";

// ==== MODEL BEGIN ====
// Pure rules only: no Herdr calls, so they can be tested outside the app.
// - Each machine owns its own item list, in LIST_FILE on that machine.
// - A space belongs to an item through the label `work.item=<id>` on its
//   terminals, stored in that machine's core.
// - Items with the same name on different machines show as one row. Rows are
//   computed on each render and never stored.
// A machine is `null` for this computer, or its name.

export const LIST_FILE = ".config/herdr-app/work-items.json";
export const LABEL = "work.item";

// "endeavour/sp1" -> "endeavour"; "sp1" -> null.
export function hostOf(id) {
  return id.includes("/") ? id.split("/")[0] : null;
}

// The id as written on its own machine: "endeavour/sp1" -> "sp1".
export function localId(id) {
  return id.includes("/") ? id.slice(id.indexOf("/") + 1) : id;
}

export function qualify(machine, id) {
  return machine ? `${machine}/${id}` : id;
}

export const machineKey = (machine) => machine ?? "";
export const rowKey = (name) => name.trim().toLowerCase();

// The list file's text -> { ok, items }. A missing or empty file is an empty
// list. Text that does not parse is not ok: never write over it.
export function parseList(text) {
  if (text == null || text.trim() === "") return { ok: true, items: [] };
  try {
    const raw = JSON.parse(text);
    const items = (Array.isArray(raw?.items) ? raw.items : [])
      .filter((item) => item && typeof item.id === "string" && typeof item.name === "string" && item.name.trim())
      .map((item, index) => ({ id: item.id, name: item.name.trim(), order: Number.isFinite(item.order) ? item.order : index }));
    return { ok: true, items };
  } catch {
    return { ok: false, items: [] };
  }
}

export function serializeList(items) {
  return JSON.stringify({ items: items.map(({ id, name, order }) => ({ id, name, order })) }, null, 2) + "\n";
}

export function nextOrder(items) {
  return items.reduce((max, item) => Math.max(max, item.order), -1) + 1;
}

// Each live space's terminals, first terminal first, and the item its first
// labeled terminal names. Order: the space's tabs, then panes() order.
//
// spaces: spaces(); panes: panes(); terminals: terminals().
// Returns Map(spaceId -> { space, machine, terminals: [address],
//   labels: Map(address -> its work.item or null), item: id | null }).
export function membership(spaces, panes, terminals) {
  const paneIndex = new Map();
  panes.forEach((pane, index) => {
    if (pane.terminal) paneIndex.set(pane.terminal, index);
  });
  const out = new Map();
  for (const space of spaces) {
    out.set(space.id, { space, machine: space.machine ?? null, terminals: [], labels: new Map(), item: null });
  }
  const rows = [];
  for (const terminal of terminals) {
    const labels = terminal.labels ?? {};
    if (terminal.state && terminal.state !== "live") continue;
    if (!labels["herdr.space"]) continue;
    const machine = hostOf(terminal.address);
    const entry = out.get(qualify(machine, labels["herdr.space"]));
    if (!entry) continue;
    const tabs = entry.space.tabs ?? [];
    const tab = tabs.findIndex((row) => row.id === qualify(machine, labels["herdr.tab"] ?? ""));
    rows.push({ entry, terminal, tab: tab < 0 ? tabs.length : tab, pane: paneIndex.get(terminal.address) ?? Infinity });
  }
  rows.sort((a, b) => a.tab - b.tab || a.pane - b.pane || a.terminal.address.localeCompare(b.terminal.address));
  for (const { entry, terminal } of rows) {
    const item = terminal.labels?.[LABEL] || null;
    entry.terminals.push(terminal.address);
    entry.labels.set(terminal.address, item);
    if (!entry.item && item) entry.item = item;
  }
  return out;
}

// One row per item name across machines.
// lists: Map(machineKey -> { machine, items }) for machines whose list is loaded.
// Returns { rows, ungrouped }. A space whose item id is not in its machine's
// list is ungrouped. Spaces on a machine whose list is not loaded are left out.
export function mergeRows(lists, members) {
  const rows = new Map();
  for (const { machine, items } of lists.values()) {
    for (const item of items) {
      const key = rowKey(item.name);
      if (!rows.has(key)) rows.set(key, { key, name: item.name, order: item.order, entries: [], spaces: [] });
      const row = rows.get(key);
      if (machine === null) row.name = item.name;
      row.order = Math.min(row.order, item.order);
      row.entries.push({ machine, item });
    }
  }
  const ungrouped = [];
  for (const entry of members.values()) {
    const list = lists.get(machineKey(entry.machine));
    if (!list) continue;
    const item = entry.item ? list.items.find((row) => row.id === entry.item) : null;
    if (!item) {
      ungrouped.push(entry.space);
      continue;
    }
    rows.get(rowKey(item.name)).spaces.push({ space: entry.space, machine: entry.machine });
  }
  const sorted = [...rows.values()].sort((a, b) => a.order - b.order || a.name.localeCompare(b.name));
  for (const row of sorted) {
    row.entries.sort((a, b) => machineKey(a.machine).localeCompare(machineKey(b.machine)));
  }
  return { rows: sorted, ungrouped };
}

// Labels to write so every terminal of a grouped space carries its item:
// new tabs and splits start without the label. Only ids the space's machine
// knows are copied, so a stale label does not spread.
export function labelFixes(members, lists) {
  const fixes = [];
  for (const entry of members.values()) {
    if (!entry.item) continue;
    const list = lists.get(machineKey(entry.machine));
    if (!list || !list.items.some((item) => item.id === entry.item)) continue;
    for (const address of entry.terminals) {
      if (entry.labels.get(address) === entry.item) continue;
      fixes.push({ address, item: entry.item });
    }
  }
  return fixes;
}

// Machines (machineKey) whose loaded list lacks an item id that one of their
// terminals names, so that list should be read again.
export function unknownItems(members, lists) {
  const out = new Set();
  for (const entry of members.values()) {
    const key = machineKey(entry.machine);
    const list = lists.get(key);
    if (!list) continue;
    for (const item of entry.labels.values()) {
      if (item && !list.items.some((each) => each.id === item)) out.add(key);
    }
  }
  return out;
}

// The one-time move from shared("work.items") to per-machine lists and labels.
// old: [{ id, name, spaces: [spaceId] }]; ready: Set of machineKey that are
// connected with a loaded list.
// Returns { wait: true } while a needed machine is not ready, else
// { lists: Map(machineKey -> { machine, items: [{ id, name }] }), labels: [{ spaceId, item }] }.
export function migrationPlan(old, ready, liveSpaceIds) {
  const lists = new Map();
  const labels = [];
  const add = (machine, id, name) => {
    const key = machineKey(machine);
    if (!lists.has(key)) lists.set(key, { machine, items: [] });
    const items = lists.get(key).items;
    if (!items.some((item) => item.id === id)) items.push({ id, name });
  };
  for (const item of old) {
    if (typeof item?.id !== "string" || typeof item?.name !== "string" || !item.name.trim()) continue;
    const spaces = Array.isArray(item.spaces) ? item.spaces.filter((id) => typeof id === "string") : [];
    if (spaces.some((id) => !ready.has(machineKey(hostOf(id))))) return { wait: true };
    const live = spaces.filter((id) => liveSpaceIds.has(id));
    if (!live.length) {
      add(null, item.id, item.name.trim());
      continue;
    }
    for (const spaceId of live) {
      add(hostOf(spaceId), item.id, item.name.trim());
      labels.push({ spaceId, item: item.id });
    }
  }
  return { wait: false, lists, labels };
}
// ==== MODEL END ====

const OLD_KEY = "work.items";
const REQUEST = "work.request";
// Renames and new items made on another device arrive by re-reading.
const REFRESH_MS = 60000;
// A terminal names an item its machine's list lacks: re-read, at most this often.
const UNKNOWN_MS = 15000;
const RETRY_MS = 30000;
const CLAIM_MS = 20000;
// Write the list next to itself, then rename: a reader never sees half a file.
const WRITE = 'mkdir -p "$(dirname "$2")" && printf "%s" "$1" > "$2.tmp" && mv -f "$2.tmp" "$2"';

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;
const machineLabel = (machine) => machine ?? "This computer";
const on = (machine) => (machine ? { on: machine } : undefined);

function nid() {
  return "wi-" + Math.random().toString(36).slice(2, 10);
}

// This computer, then every connected machine.
function readyMachines() {
  return [null, ...machines().filter((m) => m.name && m.layout === "ready").map((m) => m.name).sort()];
}

function request(kind, args) {
  setShared(REQUEST, { nonce: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, kind, ...args });
}

export default class WorkItems extends View {
  init(_props, cx) {
    if (props()?.menu) return;
    this.lists = new Map(); // machineKey -> { machine, items }
    this.broken = new Set(); // machineKey whose list does not parse
    this.homes = new Map(); // machineKey -> home folder there
    this.queue = new Map(); // machineKey -> last list write, so writes run in order
    this.reloadedAt = new Map(); // machineKey -> last re-read for an unknown item id
    this.pending = new Set(); // addresses with a label write in flight
    this.failed = new Map(); // address -> when its label write failed
    this.claim = null; // { machine, item, at, seen } after "New space" in an item
    this.editing = null; // { kind: "new" | "rename", key }
    this.input = null;
    this.draft = "";
    this.selected = null;
    this.lastActive = null;
    this.handled = null;
    this.migrating = false;
    this.migrateFailedAt = 0;
    this.readyKey = "";
    this.closed = new Set(this.stored("work.rows.closed", []));
    this.ungroupedOpen = this.stored("work.ungrouped.open", true);
    this.refresh(cx);
    cx.timer.every(REFRESH_MS, (cx) => this.refresh(cx));
    cx.timer.every(500, (cx) => this.tick(cx));
  }

  stored(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(key) ?? "null") ?? fallback;
    } catch {
      return fallback;
    }
  }

  remember() {
    localStorage.setItem("work.rows.closed", JSON.stringify([...this.closed]));
    localStorage.setItem("work.ungrouped.open", JSON.stringify(this.ungroupedOpen));
  }

  fail(title, error) {
    notify({ title, body: String(error?.message ?? error), level: "error" });
  }

  // --- Lists: one file per machine ---------------------------------------

  async pathOn(machine) {
    const key = machineKey(machine);
    if (!this.homes.has(key)) {
      if (!machine) this.homes.set(key, home());
      else {
        const result = await exec("sh", ["-c", 'printf "%s" "$HOME"'], on(machine));
        if (result.code !== 0 || !result.stdout) throw new Error(`no home folder on ${machine}`);
        this.homes.set(key, result.stdout);
      }
    }
    return `${this.homes.get(key)}/${LIST_FILE}`;
  }

  async readList(machine) {
    return parseList(await readTextFile(await this.pathOn(machine), on(machine)));
  }

  async writeList(machine, items) {
    const result = await exec("sh", ["-c", WRITE, "sh", serializeList(items), await this.pathOn(machine)], on(machine));
    if (result.code !== 0) throw new Error(result.stderr || `write failed on ${machineLabel(machine)}`);
  }

  // Re-read, change, write. Writes to one machine run one at a time.
  mutate(machine, change) {
    const key = machineKey(machine);
    const next = (this.queue.get(key) ?? Promise.resolve()).then(async () => {
      const current = await this.readList(machine);
      if (!current.ok) throw new Error(`${LIST_FILE} on ${machineLabel(machine)} does not parse; not writing over it`);
      const items = change(current.items.map((item) => ({ ...item })));
      if (JSON.stringify(items) !== JSON.stringify(current.items)) await this.writeList(machine, items);
      this.lists.set(key, { machine, items });
      return items;
    });
    this.queue.set(key, next.catch(() => {}));
    return next;
  }

  // The id of the item with this name on that machine, made if missing.
  async ensureItem(machine, name, id) {
    const key = rowKey(name);
    const items = await this.mutate(machine, (items) => (items.some((item) => rowKey(item.name) === key)
      ? items
      : [...items, { id: id ?? nid(), name: name.trim(), order: nextOrder(items) }]));
    return items.find((item) => rowKey(item.name) === key).id;
  }

  // Every connected machine's list; machines that left are dropped.
  refresh(cx) {
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      const ready = readyMachines();
      const keys = new Set(ready.map(machineKey));
      for (const key of [...this.lists.keys()]) if (!keys.has(key)) this.lists.delete(key);
      for (const machine of ready) await this.load(machine);
      this.refreshing = false;
      cx.notify();
    });
  }

  // One machine's list into memory. Unreachable or unparsable: absent.
  async load(machine) {
    const key = machineKey(machine);
    try {
      const list = await this.readList(machine);
      if (list.ok) {
        this.lists.set(key, { machine, items: list.items });
        this.broken.delete(key);
        return;
      }
      this.lists.delete(key);
      if (!this.broken.has(key)) this.fail(`Work items on ${machineLabel(machine)}`, `${LIST_FILE} does not parse`);
      this.broken.add(key);
    } catch {
      // Not reachable right now: its items are absent until the next look.
      this.lists.delete(key);
    }
  }

  // A label names an item its machine's list lacks: another device made it.
  reloadUnknown(members, cx) {
    const now = Date.now();
    for (const key of unknownItems(members, this.lists)) {
      if (now - (this.reloadedAt.get(key) ?? 0) < UNKNOWN_MS) continue;
      this.reloadedAt.set(key, now);
      const machine = this.lists.get(key).machine;
      cx.spawn(async (cx) => {
        await this.load(machine);
        cx.notify();
      });
    }
  }

  // --- Labels: membership on the machine that hosts the space --------------

  async label(address, item) {
    const result = await hc(["label", address, `${LABEL}=${item ?? ""}`]);
    if (result.code !== 0) throw new Error(result.stderr || `label failed on ${address}`);
  }

  async setSpace(spaceId, item) {
    const entry = membership(spaces(), panes(), terminals()).get(spaceId);
    for (const address of entry?.terminals ?? []) await this.label(address, item);
  }

  // Copy the label onto new tabs and splits of a labeled space.
  heal(members, cx) {
    const now = Date.now();
    const fixes = labelFixes(members, this.lists)
      .filter(({ address }) => !this.pending.has(address) && now - (this.failed.get(address) ?? 0) > RETRY_MS);
    if (!fixes.length) return;
    for (const { address } of fixes) this.pending.add(address);
    cx.spawn(async () => {
      for (const { address, item } of fixes) {
        try {
          await this.label(address, item);
          this.failed.delete(address);
        } catch {
          this.failed.set(address, Date.now());
        }
        this.pending.delete(address);
      }
    });
  }

  // After "New space" in an item: label the space that shows up on that machine.
  claimNew(members, cx) {
    const claim = this.claim;
    if (!claim) return;
    if (Date.now() - claim.at > CLAIM_MS) {
      this.claim = null;
      return;
    }
    const space = spaces().find((row) => !claim.seen.has(row.id) && (row.machine ?? null) === claim.machine);
    if (!space || !members.get(space.id)?.terminals.length) return;
    this.claim = null;
    cx.spawn(async () => {
      try {
        await this.setSpace(space.id, claim.item);
      } catch (error) {
        this.fail("Could not add the new space", error);
      }
    });
  }

  // One time: shared("work.items") becomes per-machine lists and labels.
  migrate(cx) {
    const old = shared(OLD_KEY);
    if (this.migrating || !Array.isArray(old?.items)) return;
    if (!old.items.length) {
      setShared(OLD_KEY, null);
      return;
    }
    if (Date.now() - this.migrateFailedAt < RETRY_MS * 2) return;
    const plan = migrationPlan(old.items, new Set(this.lists.keys()), new Set(spaces().map((space) => space.id)));
    if (plan.wait) return;
    this.migrating = true;
    cx.spawn(async (cx) => {
      try {
        const ids = new Map(); // "<machineKey>|<old id>" -> id on that machine
        for (const [key, { machine, items }] of plan.lists) {
          for (const item of items) ids.set(`${key}|${item.id}`, await this.ensureItem(machine, item.name, item.id));
        }
        for (const { spaceId, item } of plan.labels) {
          await this.setSpace(spaceId, ids.get(`${machineKey(hostOf(spaceId))}|${item}`));
        }
        setShared(OLD_KEY, null);
      } catch (error) {
        this.migrateFailedAt = Date.now();
        this.fail("Work items: moving to per-machine lists failed", error);
      }
      this.migrating = false;
      cx.notify();
    });
  }

  tick(cx) {
    const readyKey = readyMachines().map(machineKey).join(",");
    if (readyKey !== this.readyKey) {
      this.readyKey = readyKey;
      this.refresh(cx);
    }
    this.serve(cx);
    const members = membership(spaces(), panes(), terminals());
    this.reloadUnknown(members, cx);
    this.claimNew(members, cx);
    this.heal(members, cx);
    this.migrate(cx);
  }

  // --- Actions -------------------------------------------------------------

  rows() {
    return mergeRows(this.lists, membership(spaces(), panes(), terminals()));
  }

  act(title, work, cx) {
    cx.spawn(async (cx) => {
      try {
        await work();
      } catch (error) {
        this.fail(title, error);
      }
      cx.notify();
    });
  }

  // Actions posted by menu copies of this mod.
  serve(cx) {
    const req = shared(REQUEST);
    if (!req?.nonce || req.nonce === this.handled) return;
    this.handled = req.nonce;
    setShared(REQUEST, null);
    const row = req.key ? this.rows().rows.find((candidate) => candidate.key === req.key) : null;
    if (req.kind === "rename" && row) this.beginEdit({ kind: "rename", key: row.key }, row.name);
    if (req.kind === "delete" && row) this.act("Could not delete the item", () => this.deleteRow(row), cx);
    if (req.kind === "move") this.act("Could not move the space", () => this.moveSpace(req.space, req.name ?? null), cx);
    if (req.kind === "new-space" && row) this.act("Could not start a space", () => this.newSpace(row, req.machine ?? null), cx);
    cx.notify();
  }

  async createRow(name) {
    await this.ensureItem(null, name);
    this.selected = rowKey(name);
  }

  // Rename on every connected machine that has the item.
  async renameRow(row, name) {
    for (const { machine, item } of row.entries) {
      await this.mutate(machine, (items) => items.map((each) => (each.id === item.id ? { ...each, name: name.trim() } : each)));
    }
    if (this.selected === row.key) this.selected = rowKey(name);
  }

  // Remove the item on every connected machine, and its spaces' labels.
  async deleteRow(row) {
    for (const { machine, item } of row.entries) {
      await this.mutate(machine, (items) => items.filter((each) => each.id !== item.id));
    }
    for (const { space } of row.spaces) await this.setSpace(space.id, null);
  }

  // Into the row's item on the space's own machine (made there if missing), or out.
  async moveSpace(spaceId, name) {
    const machine = hostOf(spaceId);
    await this.setSpace(spaceId, name ? await this.ensureItem(machine, name) : null);
  }

  async newSpace(row, machine) {
    const item = await this.ensureItem(machine, row.name);
    this.selected = row.key;
    this.closed.delete(row.key);
    this.remember();
    this.claim = { machine, item, at: Date.now(), seen: new Set(spaces().map((space) => space.id)) };
    run("space.new", machine ? { machine } : {});
  }

  addSpace(row, cx) {
    const ready = readyMachines();
    if (ready.length < 2) return this.act("Could not start a space", () => this.newSpace(row, null), cx);
    openOverlay({
      mod: "work-items",
      kind: "popup",
      width: 220,
      height: 40 + ready.length * 34,
      props: { menu: "new-space", key: row.key, machines: ready, has: row.entries.map((entry) => machineKey(entry.machine)) },
    });
  }

  selectRow(row) {
    this.selected = row.key;
    this.closed.delete(row.key);
    this.remember();
    if (row.spaces.some(({ space }) => space.active)) return;
    const first = row.spaces[0]?.space;
    if (first) {
      this.lastActive = first.id;
      run("space.select", { id: first.id });
    }
  }

  // The selection follows the shown space.
  followActive(rows) {
    const active = spaces().find((space) => space.active);
    if (!active || active.id === this.lastActive) return;
    this.lastActive = active.id;
    const row = rows.find((candidate) => candidate.spaces.some(({ space }) => space.id === active.id));
    if (!row) return;
    this.selected = row.key;
    if (this.closed.delete(row.key)) this.remember();
  }

  // --- Editing ---------------------------------------------------------------

  beginEdit(editing, name) {
    this.editing = editing;
    this.draft = name;
    this.input = InputState.new({ value: name });
    if (name) this.input.set_selected_range({ start: 0, end: name.length });
    this.input.on("change", (_e, cx) => {
      this.draft = this.input.value();
      cx.notify();
    });
    this.input.on("submit", (_e, cx) => this.commitEdit(cx));
    this.input.focus();
  }

  commitEdit(cx) {
    const name = this.draft.trim();
    const editing = this.editing;
    this.cancelEdit();
    if (!name || !editing) return;
    if (editing.kind === "new") this.act("Could not add the item", () => this.createRow(name), cx);
    else {
      const row = this.rows().rows.find((candidate) => candidate.key === editing.key);
      if (row) this.act("Could not rename the item", () => this.renameRow(row, name), cx);
    }
  }

  cancelEdit() {
    this.editing = null;
    this.input = null;
  }

  // --- Menus (overlay copies) -------------------------------------------------

  menuRow(id, label, action, t, dim = false) {
    return h_flex().id(id).h(32).px(10).items_center().rounded(6).text_size(12.5).text_color(dim ? t.dim : t.foreground)
      .cursor_pointer().hover((s) => s.bg(t.hover)).on_click(action).child(label);
  }

  menu(p, t) {
    const close = () => closeOverlay(p.overlay);
    if (p.menu === "item") {
      return v_flex().id("work-item-menu").size_full().p(6).bg(t.popover).gap(2)
        .child(this.menuRow("work-rename", "Rename", () => {
          request("rename", { key: p.key });
          close();
        }, t))
        .child(this.menuRow("work-delete", "Delete item", () => {
          request("delete", { key: p.key });
          close();
        }, t));
    }
    if (p.menu === "new-space") {
      const has = new Set(p.has ?? []);
      return v_flex().id("work-new-space").size_full().p(6).bg(t.popover).gap(2)
        .child(div().px(10).h(24).text_size(11).text_color(t.dim).child("New space on"))
        .children((p.machines ?? []).map((machine) => this.menuRow(
          `new-on-${machine ?? "local"}`,
          has.has(machineKey(machine)) ? machineLabel(machine) : `${machineLabel(machine)} (adds the item there)`,
          () => {
            request("new-space", { key: p.key, machine });
            close();
          },
          t,
        )));
    }
    const targets = (p.names ?? []).filter((name) => rowKey(name) !== (p.current ? rowKey(p.current) : null));
    return v_flex().id("work-space-menu").size_full().p(6).bg(t.popover).gap(2).overflow_y_scrollbar()
      .child(div().px(10).h(24).flex_none().text_size(11).text_color(t.dim).child("Move to"))
      .children(targets.map((name) => this.menuRow(`move-${rowKey(name)}`, name, () => {
        request("move", { space: p.space, name });
        close();
      }, t)))
      .when(!targets.length, (el) => el.child(div().px(10).h(28).text_size(12).text_color(t.dim).child("No other items")))
      .when(Boolean(p.current), (el) => el.child(this.menuRow("move-out", "Remove from item", () => {
        request("move", { space: p.space, name: null });
        close();
      }, t)));
  }

  // --- Sidebar ---------------------------------------------------------------

  spaceRow(space, t, pad, rows, currentName) {
    return h_flex().id(`work-space-${space.id}`).h(28).flex_none().px(8).ml(pad).gap(8).items_center().rounded(7)
      .when(space.active, (el) => el.bg(t.selected))
      .when(!space.active, (el) => el.hover((s) => s.bg(t.hover)))
      .cursor_pointer()
      .on_click(() => {
        this.lastActive = space.id;
        run("space.select", { id: space.id });
      })
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        openOverlay({
          mod: "work-items",
          kind: "popup",
          width: 220,
          height: 280,
          props: { menu: "space", space: space.id, names: rows.map((row) => row.name), current: currentName },
        });
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

  rowHeader(row, t) {
    const open = !this.closed.has(row.key);
    const selected = this.selected === row.key;
    return h_flex().id(`work-item-${row.key}`).h(32).flex_none().px(6).gap(6).items_center().rounded(8)
      .when(selected, (el) => el.bg(t.selected))
      .when(!selected, (el) => el.hover((s) => s.bg(t.hover)))
      .cursor_pointer()
      .on_click((_e, cx) => {
        this.selectRow(row);
        cx.notify();
      })
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        openOverlay({ mod: "work-items", kind: "popup", width: 180, height: 96, props: { menu: "item", key: row.key } });
      })
      .child(div().id(`work-fold-${row.key}`).size(18).flex_none().flex().items_center().justify_center()
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => {
          cx.stop_propagation();
          open ? this.closed.add(row.key) : this.closed.delete(row.key);
          this.remember();
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/chevron-${open ? "down" : "right"}.svg`).size(12).text_color(t.dim)))
      .child(div().flex_1().min_w(0).truncate().text_size(13).font_medium().text_color(t.foreground).child(row.name))
      .child(div().flex_none().text_size(11).text_color(t.dim).child(String(row.spaces.length)))
      .child(div().id(`work-add-space-${row.key}`).size(22).flex_none().flex().items_center().justify_center().rounded(5)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
        .on_click((_e, cx) => {
          cx.stop_propagation();
          this.addSpace(row, cx);
        })
        .child(svg("mods/workspace-chrome/plus.svg").size(12).text_color(t.dim)));
  }

  // Under an item: each machine that has it, then that machine's spaces in it.
  rowBody(row, rows, t, showMachines) {
    const out = [];
    const hosts = [...new Set(row.entries.map((entry) => machineKey(entry.machine)))]
      .map((key) => row.entries.find((entry) => machineKey(entry.machine) === key).machine);
    for (const machine of hosts) {
      const mine = row.spaces.filter((entry) => entry.machine === machine).map((entry) => entry.space);
      if (showMachines) out.push(this.machineRow(machine, t, row.key));
      out.push(...mine.map((space) => this.spaceRow(space, t, showMachines ? 18 : 6, rows, row.name)));
      if (!mine.length) {
        out.push(h_flex().id(`work-empty-${row.key}-${machine ?? "local"}`).h(28).ml(showMachines ? 30 : 18).px(8).items_center().rounded(7)
          .text_size(12).text_color(t.dim).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => this.act("Could not start a space", () => this.newSpace(row, machine), cx))
          .child("New space"));
      }
    }
    return out;
  }

  ungroupedRows(ungrouped, rows, t, showMachines) {
    if (!showMachines) return ungrouped.map((space) => this.spaceRow(space, t, 0, rows, null));
    return readyMachines().flatMap((machine) => {
      const mine = ungrouped.filter((space) => (space.machine ?? null) === machine);
      if (!mine.length) return [];
      return [this.machineRow(machine, t, "ungrouped"), ...mine.map((space) => this.spaceRow(space, t, 12, rows, null))];
    });
  }

  editor(t) {
    return v_flex().id("work-editor").px(8).pb(6).flex_none()
      .child(Input.new(this.input).h(32).px(8).rounded(8).border_1().border_color(t.accent).bg(t.background)
        .text_size(12.5).text_color(t.foreground))
      .child(div().pt(4).text_size(11).text_color(t.dim).child(this.editing?.kind === "new"
        ? "New item on this computer · Enter saves · Esc cancels"
        : "Renames it on every connected machine · Enter saves · Esc cancels"));
  }

  sidebar(t) {
    const { rows, ungrouped } = this.rows();
    this.followActive(rows);
    const showMachines = readyMachines().length > 1;
    const list = [];
    if (!this.lists.has(machineKey(null))) {
      list.push(div().px(6).pt(8).text_size(12).text_color(t.dim).child("Loading…"));
    } else if (!rows.length && !this.editing) {
      list.push(div().px(6).pt(8).text_size(12).text_color(t.dim).child("Add a work item, then put spaces inside it."));
    }
    for (const row of rows) {
      list.push(this.rowHeader(row, t));
      if (this.editing?.kind === "rename" && this.editing.key === row.key) list.push(this.editor(t));
      if (!this.closed.has(row.key)) list.push(...this.rowBody(row, rows, t, showMachines));
    }
    if (ungrouped.length) {
      list.push(h_flex().id("work-ungrouped").h(26).px(6).mt(8).items_center().gap(6).cursor_pointer()
        .on_click((_e, cx) => {
          this.ungroupedOpen = !this.ungroupedOpen;
          this.remember();
          cx.notify();
        })
        .child(svg(`mods/workspace-chrome/chevron-${this.ungroupedOpen ? "down" : "right"}.svg`).size(12).text_color(t.dim))
        .child(div().text_size(11).text_color(t.dim).child(`Ungrouped · ${ungrouped.length}`)));
      if (this.ungroupedOpen) list.push(...this.ungroupedRows(ungrouped, rows, t, showMachines));
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
            this.beginEdit({ kind: "new" }, "");
            cx.notify();
          })
          .child(svg("mods/workspace-chrome/plus.svg").size(14))))
      .when(this.editing?.kind === "new", (el) => el.child(this.editor(t)))
      .child(v_flex().flex_1().min_h(0).px(8).pb(12).gap(2).overflow_y_scrollbar().mode("always").children(list));
  }

  render() {
    const t = theme();
    const p = props() ?? {};
    if (p.menu) return this.menu(p, t);
    shared(REQUEST); // re-render when a menu posts an action
    if (narrow()) {
      const { rows } = this.rows();
      return v_flex().size_full().bg(t.chrome).pt(8).gap(4).items_center()
        .children(rows.map((row) => div().id(`work-rail-${row.key}`).size(28).rounded(7)
          .flex().items_center().justify_center().text_size(11).font_bold()
          .text_color(this.selected === row.key ? t.foreground : t.dim)
          .bg(this.selected === row.key ? t.selected : t.chrome)
          .cursor_pointer()
          .on_click(() => this.selectRow(row))
          .child((row.name[0] ?? "?").toUpperCase())));
    }
    return this.sidebar(t);
  }
}
