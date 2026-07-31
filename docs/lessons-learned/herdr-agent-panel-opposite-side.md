# Herdr: agents panel on the opposite side from the spaces list

**Date:** 2026-07-31
**Status:** Not supported by herdr (verified against installed 0.7.5 and latest upstream preview). No config change made in this repo.

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
