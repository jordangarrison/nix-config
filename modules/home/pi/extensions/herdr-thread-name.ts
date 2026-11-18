// herdr-thread-name: give each pi agent in Herdr a name that says what it works on.
//
// Herdr's T3 sidebar, Inbox and tabs name an agent by the `pi.session` label on
// its herdr-core terminal first, then by its tab name. Nothing set that label,
// so agents showed as tab numbers ("1"), roles ("worker") or just "Pi".
//
// This extension, only for an interactive pi in a herdr-core terminal:
//   1. While the session has no name, it turns on the `name_session` tool.
//      With the first prompt it adds a hidden message that asks the agent
//      to name the work before it starts: a rule in the system prompt alone
//      was ignored in testing.
//   2. When the session name changes (the tool, /name, --name), it copies the
//      name to `pi.session` on $HC_TERMINAL_ID, or removes the label when the
//      new session has no name.
//   3. It renames the agent's tab when Herdr still calls it by its number and
//      the agent is alone in it. A tab someone named stays as it is.
// Outside a herdr-core terminal, or in print/json/rpc mode, it does nothing.
// Failures to reach `hc` or `herdr-app` are ignored: naming is never worth
// breaking a session for.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const TOOL = "name_session";
const MAX_LENGTH = 60;
const TIMEOUT_MS = 5000;
const REQUEST =
  "Before you start on this request, call name_session once: 2 to 6 words that name the work, " +
  'with the ticket or PR first when there is one (for example "SRE-1127 CloudSearch TF import"). ' +
  "Herdr shows this name when you ask the user for input.";

/** One line, trimmed, at most MAX_LENGTH characters. */
export function cleanName(raw: string): string {
  return raw.replace(/\s+/g, " ").trim().slice(0, MAX_LENGTH).trim();
}

/**
 * The id of the tab to rename for this terminal, from `herdr-app ls`: only a
 * tab Herdr still calls by its number ("1"), with this terminal alone in it.
 */
export function tabToRename(ls: any, terminal: string): string | null {
  for (const space of ls?.spaces ?? []) {
    for (const tab of space?.tabs ?? []) {
      const terminals = (tab?.terminals ?? []).map((t: any) => t?.terminal);
      if (!terminals.includes(terminal)) continue;
      const unnamed = /^\d+$/.test(String(tab?.name ?? ""));
      return unnamed && terminals.length === 1 ? tab.id : null;
    }
  }
  return null;
}

export default function herdrThreadName(pi: ExtensionAPI) {
  const terminal = process.env.HC_TERMINAL_ID;
  if (!terminal) return;

  let interactive = false;
  // Ask once per session: an agent that does not name it is not asked again.
  let asked = false;

  const run = async (command: string, args: string[]) => {
    try {
      return await pi.exec(command, args, { timeout: TIMEOUT_MS });
    } catch {
      return null;
    }
  };

  const setToolActive = (on: boolean) => {
    const active = pi.getActiveTools();
    const has = active.includes(TOOL);
    if (on && !has) pi.setActiveTools([...active, TOOL]);
    if (!on && has) pi.setActiveTools(active.filter((name) => name !== TOOL));
  };

  const renameTab = async (name: string) => {
    const ls = await run("herdr-app", ["ls"]);
    if (!ls || ls.code !== 0) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(ls.stdout);
    } catch {
      return;
    }
    const tab = tabToRename(parsed, terminal);
    if (tab) await run("herdr-app", ["do", "tab.rename", "--id", tab, "--name", name]);
  };

  // One place that makes Herdr match the session's name (or its lack of one).
  const sync = async (name: string | undefined) => {
    setToolActive(!name);
    await run("hc", ["label", terminal, `pi.session=${name ?? ""}`]);
    if (name) await renameTab(name);
  };

  pi.registerTool({
    name: TOOL,
    label: "Name session",
    description:
      "Name this session after the work it does. Herdr shows the name in its sidebar, Inbox and tab.",
    promptSnippet: "Name this session after its work (shown in Herdr)",
    promptGuidelines: [
      "This session has no name yet. Call name_session once, before other work, in your first reply: " +
        "2 to 6 words that name the work, with the ticket or PR first when there is one " +
        '(for example "SRE-1127 CloudSearch TF import"). Name the work, not your role ' +
        '(not "worker", "handoff" or "coord").',
    ],
    defaultActive: false,
    parameters: Type.Object({
      name: Type.String({ description: "2 to 6 words naming the work, ticket or PR first" }),
    }),
    async execute(_toolCallId: string, params: { name: string }) {
      const name = cleanName(params.name ?? "");
      if (!name) throw new Error("name_session needs a non-empty name");
      pi.setSessionName(name);
      return { content: [{ type: "text", text: `Session named "${name}".` }], details: { name } };
    },
  } as any);

  pi.on("session_start", async (_event: any, ctx: any) => {
    interactive = ctx.mode === "tui";
    asked = false;
    if (!interactive) {
      setToolActive(false);
      return;
    }
    await sync(pi.getSessionName() ?? undefined);
  });

  pi.on("session_info_changed", async (event: any) => {
    if (!interactive) return;
    await sync(event.name ?? undefined);
  });

  pi.on("before_agent_start", async (event: any) => {
    if (!interactive || asked || event.messageType !== "user" || pi.getSessionName()) return;
    asked = true;
    return { message: { customType: "herdr-thread-name", content: REQUEST, display: false } };
  });
}
