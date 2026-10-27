import type { ExtensionAPI, Theme, ToolRenderContext } from "@earendil-works/pi-coding-agent";
import type { Component } from "@earendil-works/pi-tui";
import { Text } from "@earendil-works/pi-tui";

// pi-foldable-tools cuts the bash call header at 120 characters. Pi already
// makes the header clickable and passes the block's expanded state (click or
// ctrl+o) to renderCall, so show the whole command once the block is expanded.
// Collapsed blocks keep whatever header the underlying renderer draws.

// Wide enough that render() only reports whether the header has content.
const PROBE_WIDTH = 200;

function fullCall(args: { command?: unknown; timeout?: unknown }, theme: Theme): string {
	let text = theme.fg("toolTitle", theme.bold("$ ")) + theme.fg("accent", String(args.command ?? ""));
	if (args.timeout) text += theme.fg("dim", ` (timeout ${args.timeout}s)`);
	return text;
}

export default function (pi: ExtensionAPI) {
	pi.registerToolRenderer((toolName, next) => {
		const base = next();
		if (toolName !== "bash" || !base?.renderCall) return base;
		const renderCall = base.renderCall;

		return {
			...base,
			renderCall(args, theme, context: ToolRenderContext) {
				const component: Component = renderCall(args, theme, context);
				// An empty header means the block is hidden (pi-foldable-tools'
				// "hidden" mode); leave it hidden.
				if (!context.expanded || component.render(PROBE_WIDTH).length === 0) return component;
				const text = component instanceof Text ? component : new Text("", 0, 0);
				text.setText(fullCall(args, theme));
				return text;
			},
		};
	});
}
