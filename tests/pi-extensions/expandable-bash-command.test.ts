// Regression tests for modules/home/pi/extensions/expandable-bash-command.ts.
// Run with `nix build .#checks.x86_64-linux.pi-extensions`.
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Text } from "@earendil-works/pi-tui";
import expandableBashCommand from "../extensions/expandable-bash-command.ts";

const theme = {
  fg: (_token: string, text: string) => `\x1b[38;5;2m${text}\x1b[39m`,
  bold: (text: string) => `\x1b[1m${text}\x1b[22m`,
} as any;

const strip = (line: string) => line.replace(/\x1b\[[0-9;]*m/g, "");

type Renderer = (...args: any[]) => any;

// Mirrors pi-foldable-tools: a reused Text, the command cut at 120 characters,
// and an empty header in its "hidden" mode.
function foldableBase(hidden = false) {
  return {
    name: "bash",
    renderCall(args: { command: string }, _theme: unknown, context: { lastComponent?: Text }) {
      const text = context.lastComponent ?? new Text("", 0, 0);
      const cmd = args.command.length > 120 ? `${args.command.slice(0, 117)}...` : args.command;
      text.setText(hidden ? "" : `$ ${cmd}`);
      return text;
    },
    renderResult: () => new Text("", 0, 0),
  };
}

function resolve(toolName: string, base: unknown) {
  const resolvers: Renderer[] = [];
  expandableBashCommand({ registerToolRenderer: (resolver: Renderer) => resolvers.push(resolver) } as any);
  assert.equal(resolvers.length, 1);
  return resolvers[0](toolName, () => base);
}

const context = (overrides: Record<string, unknown> = {}) =>
  ({ expanded: false, isPartial: false, lastComponent: undefined, ...overrides }) as any;

function header(renderers: any, args: unknown, overrides: Record<string, unknown> = {}, width = 400): string {
  return renderers
    .renderCall(args, theme, context(overrides))
    .render(width)
    .map((line: string) => strip(line).trimEnd())
    .join("\n");
}

const longCommand = `cd /home/jordangarrison/.herdr/worktrees/nix-config/fix-sre-review-bot-nix-mcp && nh os build . --no-nom 2>&1 | grep -E "error|warning" | tail -40`;

describe("expandable-bash-command", () => {
  it("keeps the underlying collapsed header", () => {
    assert.equal(header(resolve("bash", foldableBase()), { command: longCommand }), `$ ${longCommand.slice(0, 117)}...`);
  });

  it("shows the whole command when expanded", () => {
    const text = header(resolve("bash", foldableBase()), { command: longCommand, timeout: 3600 }, { expanded: true });
    assert.equal(text, `$ ${longCommand} (timeout 3600s)`);
  });

  it("shows every line of a multi-line command when expanded", () => {
    const command = `python3 - <<'PYEOF'\np = 'docs/runbooks/hermes.md'\nprint(open(p).read())\nPYEOF`;
    assert.equal(header(resolve("bash", foldableBase()), { command }, { expanded: true }), `$ ${command}`);
  });

  it("wraps the expanded command to the terminal width", () => {
    const lines = resolve("bash", foldableBase())
      .renderCall({ command: longCommand }, theme, context({ expanded: true }))
      .render(60)
      .map(strip);
    assert.ok(lines.length > 1);
    assert.ok(lines.every((line: string) => line.length <= 60));
    // Long words wrap mid-word, so compare without whitespace.
    assert.equal(lines.join("").replace(/\s+/g, ""), `$ ${longCommand}`.replace(/\s+/g, ""));
  });

  it("collapses again on the reused component", () => {
    const renderers = resolve("bash", foldableBase());
    const expanded = renderers.renderCall({ command: longCommand }, theme, context({ expanded: true }));
    const collapsed = renderers.renderCall({ command: longCommand }, theme, context({ lastComponent: expanded }));
    assert.equal(collapsed, expanded);
    assert.equal(strip(collapsed.render(400)[0]).trimEnd(), `$ ${longCommand.slice(0, 117)}...`);
  });

  it("leaves a hidden block hidden", () => {
    const renderers = resolve("bash", foldableBase(true));
    assert.deepEqual(renderers.renderCall({ command: longCommand }, theme, context({ expanded: true })).render(80), []);
  });

  it("passes other tools through unchanged", () => {
    const base = { name: "read", renderCall: () => new Text("read", 0, 0) };
    assert.equal(resolve("read", base), base);
    assert.equal(resolve("bash", undefined), undefined);
  });
});
