import { spawn } from "node:child_process";
import { accessSync, constants, mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { hyperlink, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// show_html: the model writes a self-contained HTML page and the person gets
// it as a live, interactive window (scripts, clicks, forms all work).
//
// The page is saved under ~/.cache/pi-html/ and opened in a chromeless
// browser window. On Linux with Brave on PATH that is `brave --app=<url>`.
// Brave names such a window `brave-<path with / as _>-Default`, so the niri
// window rule on `_pi-html_` (modules/home/niri) makes it float, centered.
// Elsewhere the system opener is used. PI_HTML_OPEN overrides the opener: it
// is a shell command, and the page's file:// URL is appended as one argument.
//
// /html reopens the latest page in this session branch; /html list picks one.

const PAGE_DIR = join(homedir(), ".cache", "pi-html");
const TOOL_NAME = "show_html";

interface Page {
	path: string;
	title: string;
}

function slug(title: string): string {
	const s = title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
	return s.slice(0, 40) || "page";
}

function savePage(title: string, html: string, id: string): Page {
	mkdirSync(PAGE_DIR, { recursive: true });
	const path = join(PAGE_DIR, `${slug(title)}-${id.replace(/[^a-zA-Z0-9]/g, "").slice(-8)}.html`);
	writeFileSync(path, html);
	return { path, title };
}

function onPath(program: string): boolean {
	return (process.env.PATH ?? "").split(delimiter).some((dir) => {
		try {
			accessSync(join(dir, program), constants.X_OK);
			return true;
		} catch {
			return false;
		}
	});
}

function openerFor(url: string): [string, string[]] {
	const custom = process.env.PI_HTML_OPEN;
	if (custom) return ["sh", ["-c", `${custom} "$1"`, "sh", url]];
	if (process.platform === "darwin") return ["open", [url]];
	if (onPath("brave")) return ["brave", [`--app=${url}`]];
	return ["xdg-open", [url]];
}

// Detached: a first browser instance would otherwise live as pi's child.
function openPage(page: Page): Promise<void> {
	const [cmd, args] = openerFor(pathToFileURL(page.path).href);
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args, { detached: true, stdio: "ignore" });
		child.once("error", reject);
		child.once("spawn", () => {
			child.unref();
			resolve();
		});
	});
}

function isPage(value: unknown): value is Page {
	const v = value as Partial<Page> | undefined;
	return typeof v?.path === "string" && typeof v?.title === "string";
}

// Pages shown in the current branch, oldest first.
function branchPages(ctx: ExtensionContext): Page[] {
	const pages: Page[] = [];
	for (const entry of ctx.sessionManager.getBranch() as any[]) {
		const msg = entry?.type === "message" ? entry.message : undefined;
		if (msg?.role === "toolResult" && msg.toolName === TOOL_NAME && isPage(msg.details)) pages.push(msg.details);
	}
	return pages;
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: TOOL_NAME,
		label: "Show HTML",
		description:
			"Open a self-contained HTML page for the user in a floating, interactive browser window. " +
			"Inline all CSS and JavaScript; the page is a local file, so only absolute https:// URLs load from the network.",
		promptSnippet: "Show the user an interactive HTML page in a floating window",
		promptGuidelines: [
			"Use show_html when the user asks for HTML, a visual, or something interactive, or when a diagram, chart, or interactive prototype explains the answer far better than text. Keep the chat reply short; do not repeat the page in prose.",
		],
		parameters: Type.Object({
			title: Type.String({ description: "Short page title, also used in the file name" }),
			html: Type.String({ description: "The complete HTML document, starting with <!doctype html>" }),
		}),
		async execute(toolCallId, params) {
			const page = savePage(params.title, params.html, toolCallId);
			await openPage(page);
			return {
				content: [{ type: "text", text: `Opened "${page.title}" in a window for the user (${page.path}).` }],
				details: page,
			};
		},
		renderCall(args, theme, context) {
			const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
			text.setText(theme.fg("toolTitle", theme.bold("show_html ")) + theme.fg("accent", String(args.title ?? "")));
			return text;
		},
		renderResult(result, _options, theme, context) {
			const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
			const page = result.details;
			if (context.isError || !isPage(page)) {
				const msg = result.content.find((c) => c.type === "text");
				text.setText(theme.fg("error", msg?.type === "text" ? msg.text : "show_html failed"));
				return text;
			}
			const link = hyperlink(page.path, pathToFileURL(page.path).href);
			text.setText(`${theme.fg("dim", link)}  ${theme.fg("muted", "/html to reopen")}`);
			return text;
		},
	});

	pi.registerCommand("html", {
		description: "Reopen the latest show_html page (/html list to pick one)",
		handler: async (args, ctx) => {
			const pages = branchPages(ctx);
			if (pages.length === 0) {
				ctx.ui.notify("No show_html pages in this session yet.", "info");
				return;
			}
			let page = pages[pages.length - 1];
			if (args.trim() === "list") {
				const labels = pages.map((p, i) => `${i + 1}. ${p.title}`).reverse();
				const choice = await ctx.ui.select("Reopen page:", labels);
				if (!choice) return;
				page = pages[Number.parseInt(choice, 10) - 1];
			}
			try {
				await openPage(page);
			} catch (err) {
				ctx.ui.notify(`Could not open ${page.path}: ${(err as Error).message}`, "error");
			}
		},
	});
}
