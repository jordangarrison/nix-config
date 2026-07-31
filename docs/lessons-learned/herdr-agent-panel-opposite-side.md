# Herdr: agents panel on the opposite side from the spaces list

**Date:** 2026-07-31 (plugin/sidecar research added same day)
**Status:** Not supported by herdr core or plugin v1 (verified against installed 0.7.5 and latest upstream preview). A sidecar-TUI plugin is feasible and is the recommended build path if we want this. No config change made in this repo; tracked in the repo issue referenced below.

## The ask

Place herdr's agents menu/status list on the opposite side of the screen from the
project/workspace ("spaces") list, so the full spaces list lives on one edge and the
full agent list on the other.

## Finding: not supported

In herdr, the spaces list and the agents panel are **two sections of a single sidebar
column** — they cannot be split apart, and the sidebar itself cannot even be moved to
the right edge. Verified four ways against the installed version (0.7.5, the latest
stable as of 2026-07-31):

1. **`herdr --default-config`** — the entire layout surface under `[ui]` is:
   `sidebar_width`, `sidebar_min_width`, `sidebar_max_width`, `sidebar_start_collapsed`,
   `sidebar_collapsed_mode`, `mobile_width_threshold`, `agent_panel_sort`, plus
   `[ui.sidebar.agents]` / `[ui.sidebar.spaces]` row-content templates. Width, collapse,
   ordering *within* the panel, and row content are configurable; placement is not.
2. **Binary config schema** — the serde field-name table in the 0.7.5 binary
   (`strings` on `/nix/store/...-herdr-0.7.5/bin/herdr`) contains no
   `sidebar_side`/`sidebar_position`/agent-panel-placement key. The only `position`
   fields are toast popups (`ui.toast.herdr.position`, `ui.toast.clipboard.position`).
3. **Official docs** — herdr.dev's configuration guide describes sidebar sizing,
   collapsed mode, agent-panel ordering, and row styling only; nothing relocates the
   sidebar or separates its sections.
4. **Latest upstream preview** (`preview-2026-07-29-44b3adb12552`, ahead of 0.7.5) —
   release notes contain nothing about sidebar/panel placement.

## Upstream state

- **Discussion [herdrdev/herdr#1465](https://github.com/herdrdev/herdr/discussions/1465)**
  (Ideas, 2026-07-16): proposes `ui.sidebar_side = "left" | "right"` for the whole
  sidebar, with an implementation offer. Community +1s, no maintainer response yet.
  This is the *whole-sidebar* flip — necessary context but less than the split ask.
- **Issue [#2039](https://github.com/herdrdev/herdr/issues/2039)**: asked merely to
  reorder the two sections vertically (`sidebar_section_order`). Closed by the repo
  bot — **the issue tracker is bugs-only; feature requests must go to Discussions**.
  Useful detail from that thread: `session.json` already persists
  `sidebar_section_split` (the ratio between the two sections), so the split between
  sections is a first-class runtime property; the sections just can't be re-homed.

## Best actionable upstream path

1. Open an **Ideas discussion** at <https://github.com/herdrdev/herdr/discussions>
   (not an issue — #2039 shows non-bugs get bot-closed). Propose something like
   `ui.agent_panel_side = "sidebar" | "opposite"` (agents panel as its own column on
   the edge opposite the sidebar), explicitly referencing and building on #1465's
   `sidebar_side` so the two placements compose.
2. Watch/upvote **#1465** — if whole-sidebar placement lands, an agents-panel split
   becomes a smaller incremental change to the same layout code.

## Mitigations available today (already applied in this repo)

- `ui.agent_panel_sort = "priority"` floats agents needing attention to the top of the
  agents section (set in `users/jordangarrison/home.nix`).
- The spaces/agents boundary within the sidebar can be dragged in the UI; the ratio
  persists in runtime `session.json` (unmanaged, so it survives rebuilds).
- `sidebar_max_width` can be raised if the combined list feels cramped.

Deliberately **no** speculative `settings` keys were added to `programs.herdr` —
herdr ignores unknown config keys silently, so a made-up `sidebar_side` would just be
dead weight that looks load-bearing.

---

## Follow-up research: can a plugin provide this? (2026-07-31)

Deep-research pass (multi-agent, 17 primary sources, 25 claims adversarially
verified: 22 confirmed / 3 refuted) plus direct inspection of the installed
binary's API schema (`herdr api schema --json`, protocol 17).

### Plugin v1 cannot render real UI

- herdr.dev/docs/plugins, verbatim: *"Runtime action registration and native
  non-terminal plugin UI are not part of plugin v1."* Plugins are
  `herdr-plugin.toml`-declared bundles of actions, event hooks, link handlers,
  startup commands, and **terminal panes**.
- Plugin pane placements are exactly `overlay | popup | split | tab | zoomed` —
  no sidebar/edge slot. Binary error strings confirm: split/zoomed panes target
  an existing pane (`target_pane_id`); width/height percentages only apply to
  `popup`.
- The sidebar is one `Rect` in `src/ui/sidebar.rs`
  (`expanded_sidebar_sections(area, split_ratio)`), split top/bottom with the
  ratio clamped 0.1–0.9. Placement is a core layout change, not a config gap.
- Upstream proposals all open, none landed: discussion #1465 (`sidebar_side`
  left/right, 9 upvotes), #1220 (plugin sidebar slots), #1609 (plugin-owned
  sidebar section — maintainer steering toward a narrow *text-only summary
  API*, which still would not allow a custom panel). CONTRIBUTING requires a
  Discussion before any feature PR.

### But the socket API has everything a sidecar panel needs

Confirmed in both docs and the installed binary's schema:

- State: `agent.list` / `agent.get`, semantic status
  (`idle|working|blocked|done|unknown`) reported by integrations via
  `pane.report_agent` — no screen scraping.
- Live updates: `events.subscribe` push stream with
  `pane.agent_status_changed`, `pane.agent_detected`, `workspace.focused`,
  `tab.focused`, `layout.updated`. Caveat: subscription dies with the
  connection (no replay) — a panel needs reconnect + `agent.list` resync.
- Interactivity: `agent.focus` (jump to agent), `agent.prompt`.
- Plumbing: plugin pane processes receive `HERDR_SOCKET_PATH` (+ active
  workspace/tab/pane IDs) in their environment; `layout.set_split_ratio` sets
  a split pane's width after open.

### Shipped precedent

Community plugin `herdr-reviewr` (persiyanov/herdr-reviewr) markets itself as
a "sidebar for herdr" and is actually a Rust TUI in a manifest-declared split
pane with configurable placement — exactly this pattern. (Medium confidence:
verifier-summarized rather than direct-fetched; treat its config keys as
indicative.)

### Feasible design: `herdr-agents-panel` plugin

A TUI binary (packaged in this repo like our other custom packages) that:
1. connects to `HERDR_SOCKET_PATH`, `agent.list` → renders the agent queue
   (priority-sorted, mirroring `ui.agent_panel_sort = "priority"`),
2. subscribes to `pane.agent_status_changed` for live updates,
3. calls `agent.focus` on selection,
4. is declared as a plugin pane with `placement = "split"`, opened right via a
   keybound action, width set with `layout.set_split_ratio`.

Known gaps vs. a native sidebar: the pane lives **per-workspace layout** (an
event hook on `workspace.focused` can auto-open/re-focus it), and it occupies
normal grid space with its position persisted in runtime `session.json`.

Open questions (from the research pass): does the pinned pane survive
`pane_history`/restore cleanly or need a manifest startup hook; how stable is
right-edge geometry across pane churn; the final shape of #1609's summary API;
maintainer appetite for a #1465 PR.

**Decision 2026-07-31: no action for now.** If/when we want it: build the
sidecar plugin (track 1) and upvote/back #1465 upstream (track 2).
