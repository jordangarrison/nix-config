---
name: browser-testing-walkthrough
description: Use when manually testing a feature in the browser with GIF recording, after implementation is complete and automated tests pass. Use when the user asks to "manually test", "walkthrough", "record a demo", or "test in the browser".
---

# Browser Testing Walkthrough

Record a GIF walkthrough of manual browser testing using Claude-in-Chrome MCP tools.

## When to Use

- Feature implementation is complete, automated tests pass
- Need visual verification before PR or demo
- User asks for a recorded walkthrough or manual test

## Setup Sequence

Always follow this exact order:

1. `tabs_context_mcp` — see existing browser state
2. `tabs_create_mcp` — create a fresh tab (never reuse tabs from prior sessions)
3. `gif_creator` with `start_recording` — begin recording before any navigation
4. Authenticate — navigate to dev login route or sign-in page

## Tool Selection

| Goal | Tool | Notes |
|------|------|-------|
| Go to a URL | `navigate` | For initial page loads, direct routes |
| Click in-app links | `computer` with `left_click` | More realistic user behavior, captured in GIF |
| Go back | `navigate` with `"back"` | Browser history |
| Visual check + GIF frame | `computer` with `screenshot` | Each screenshot = one GIF frame |
| Inspect small elements | `computer` with `screenshot` + `region` | Zoom. NOT captured as GIF frame |
| Find a click target | `find` with natural language | Best for small/ambiguous targets like × buttons |
| Read DOM structure | `read_page` | Accessibility tree when visual isn't enough |
| Click precisely | `computer` with `left_click` + `ref` | Use ref from `find` results |
| Select input contents | `computer` with `triple_click` | Then `type` to replace |
| Text input | `computer` with `type` | After clicking/selecting the input |
| Tab between fields | `computer` with `key` "Tab" | Field traversal, triggers phx-change |
| Wait for page | `computer` with `wait` 1s | Default. Only 2-3s for heavy loads |

## GIF Frame Budget

50 frames max. Each `screenshot` call = 1 frame.

**Budget strategy:**
- 2-3 frames per flow for context (before action, after action)
- Extra frames before/after important interactions for smooth playback
- `zoom` screenshots do NOT consume frames — use freely for verification

## Testing Flow Structure

For each feature flow:

1. **Navigate** to the starting page
2. **Screenshot** to capture initial state (GIF frame)
3. **Interact** — click, type, select
4. **Wait** 1s for page transitions
5. **Screenshot** to capture result (GIF frame)
6. **Zoom** into specific elements to verify details (not a GIF frame)
7. Repeat for each interaction in the flow

## Bug Discovery During Testing

When something doesn't work:

1. Read the relevant source code to understand current implementation
2. Identify root cause
3. Fix it, compile, format-check
4. Re-test in browser to confirm
5. **Restore original data state** after verification (undo test edits)

## Export and Save

```
gif_creator → stop_recording
gif_creator → export with download: true, filename: "descriptive-name.gif"
```

Move from `~/Downloads/` to project docs directory (e.g., `docs/recordings/`).

**Export options:** click indicators, action labels, progress bar — all enabled by default.

## Writing the Test Prompt

When giving an agent a testing prompt, structure it as:

```
Manually test [feature] on [base URL] and record a GIF.

## Setup
1. Navigate to [login URL] to authenticate
2. Navigate to [starting page]

## Flow 1: [Name]
1. [Step with expected outcome]
2. [Step with expected outcome]
...

## Flow N: [Name]
...

Name the GIF [descriptive-name].gif
```

**Tips for good prompts:**
- Name specific test users or data that should exist (from seeds)
- Call out edge cases to verify (error states, empty states, warnings)
- Specify which elements to zoom into for verification
- Keep to 3-5 flows — more than that and the 50-frame budget gets thin

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reusing tabs from prior session | Always `tabs_create_mcp` for a fresh tab |
| Forgetting to start recording | `gif_creator start_recording` BEFORE first navigation |
| Burning frames on zooms | `zoom` doesn't add GIF frames — use `screenshot` only for frames you want |
| Long waits everywhere | Default 1s. Only 2-3s for genuinely heavy page loads |
| Not restoring test data | Reset edited values after verification |
| Guessing coordinates for small targets | Use `find` with natural language, then `left_click` with `ref` |
| Recording too many flows | Budget 50 frames across all flows. 3-5 focused flows is ideal |
