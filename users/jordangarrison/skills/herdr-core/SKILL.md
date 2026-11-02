---
name: herdr-core
description: "Run programs and coding agents in persistent herdr-core terminals with hc: start, read, message, wait on, and clean up terminals and child agents, locally or on other machines. Use when HC_TERMINAL_ID is set and work needs a background terminal, a dedicated agent, or the Herdr app's terminals. Not the older herdr TUI (HERDR_ENV)."
---

# herdr-core (`hc`)

herdr-core updates itself outside Nix (`~/.local/bin/herdr-core`, linked as
`hc`), so its manual is not copied here. Load the current manual before you
use it:

```bash
test -n "${HC_TERMINAL_ID:-}" && hc --skill
```

If `HC_TERMINAL_ID` is empty, this session is not in a herdr-core terminal.
Do not use `hc` to control panes in that case.

Follow the printed manual. `$HC_TERMINAL_ID` is your address. To change what
the person sees in the window (spaces, tabs, panes), use [[herdr-app]].
