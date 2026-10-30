# Slack calls (Flo executor)

Shared by [[slack-pr-review]], [[infra-reviews]], and [[sre-review-thread]].

Slack goes through the `executor-flo` MCP server, not a direct Slack server. Pi's built-in MCP exposes that server as `mcp__executor_flo__execute`. Call it from `codemode`. The JavaScript argument runs inside Executor, not in Pi.

The account segment of the tool path differs per user, so resolve it once per session, inside that program:

```js
const account = await tools.mcp__executor_flo__execute({
  code: `
    const { items } = await tools.search({ query: "slack_read_thread", limit: 10 });
    const path = items.map(i => i.path).find(p => /^slack_mcp\\.user\\.[^.]+\\.slack_read_thread$/.test(p));
    if (!path) return null;
    return path.split(".")[2];
  `,
});
```

Then call Slack tools inside the same Executor program: `tools.slack_mcp.user[<account>].<tool>({ ... })`. One program can make several calls. An inner call returns `{ ok, data }` instead of throwing. On `ok: false`, `error.code` and `error.message` say why (`oauth_reauth_required` means Slack needs reconnecting in the FloSports Executor dashboard). On success, `data.content[0].text` holds Slack's response text. If the search finds no `slack_mcp` path, Slack isn't connected in Executor: stop and say so.

## Tools used

| Tool | Arguments | Use |
|---|---|---|
| `slack_read_channel` | `channel_id`, `limit`, optional `oldest` / `cursor` | Top-level messages, newest first. Each shows `Message TS`, author `(U…)`, `Reactions:` line, and `Thread: N replies`. |
| `slack_read_thread` | `channel_id`, `message_ts`, `limit`, optional `cursor` | Thread parent + replies. Page with `cursor` until "no more messages". |
| `slack_read_canvas` | `canvas_id` | Canvas markdown (channel instructions). The response text is JSON: `JSON.parse` it and read `markdown_content` before matching lines, or a pattern runs across the escaped `\n` and picks the wrong emoji. |
| `slack_send_message` | `channel_id`, `message`, optional `thread_ts` | Post. Pass `thread_ts` to reply in a thread. |
| `slack_add_reaction` | `channel_id`, `message_ts`, `emoji` | Emoji name **without** colons. A duplicate succeeds silently. There is no remove-reaction tool: a reaction, once added, stays. |
| `slack_get_reactions` | `channel_id`, `message_ts` | Who reacted with what: `:eye-twitch: × 1 — Jordan Garrison (UQ69UGHKM)`. |
| `slack_search_users` | `keywords: ["<email>"]` | Resolve the current user's Slack ID from `userEmail`. |

## Reading reactions

The `Reactions:` line in channel/thread output lists emoji and counts only (e.g. `Reactions: eye-twitch (2), mega-approved (1)`), not who reacted. When you need to know whether *you* or someone else reacted, call `slack_get_reactions` for that message. Only call it for messages that already have a `Reactions:` line.

## Permalinks

If a response has no permalink, build one:

```
https://flosports.slack.com/archives/<channel_id>/p<ts without the dot>
https://flosports.slack.com/archives/<channel_id>/p<reply ts without the dot>?thread_ts=<parent ts>&cid=<channel_id>
```
