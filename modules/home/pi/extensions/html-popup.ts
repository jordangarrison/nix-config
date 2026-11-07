import { execFile, spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { accessSync, constants, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { homedir } from "node:os";
import { basename, delimiter, join } from "node:path";
import { pathToFileURL } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { hyperlink, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

// show_html: the model writes a self-contained HTML page and the person gets
// it as a live, interactive window (scripts, clicks, forms all work). The page
// can answer back: window.pi.reply(text) sends text to the chat as the
// person's next message.
//
// Pages are saved under ~/.cache/pi-html/. While pi runs, a server inside this
// extension serves them at http://127.0.0.1:<port>/pi-html/<file>. It listens
// on loopback only, serves only files in that folder, and accepts a reply only
// with this process's random token, which it writes into each page it serves.
// Other local pages cannot read the token, and a cross-origin request with the
// token header needs a CORS preflight that the server never answers.
//
// Pages open in a chromeless browser window. On Linux with Brave on PATH that
// is `brave --app=<url>`. Brave names such a window after the URL path with /
// as _, so the niri window rule on `_pi-html_` (modules/home/niri) makes it
// float, centered. Elsewhere the system opener is used. PI_HTML_OPEN overrides
// the opener: a shell command; the page URL is appended as one argument.
//
// A page opens only while the person looks at this agent: in Herdr
// ($HC_TERMINAL_ID set), the focused agent must be this terminal and, under
// niri, the Herdr window must have focus. Otherwise the page waits and opens
// when they come back (checked every FOCUS_POLL_MS). If a check fails, the page
// opens, so it is never lost. Outside Herdr pages open at once.
//
// /html reopens the latest page in this session branch; /html list picks one.
// Both open at once. The server ends with the session, so a page opened
// earlier cannot reply until /html opens it again.

const PAGE_DIR = join(homedir(), ".cache", "pi-html");
const PAGE_NAME = /^[a-z0-9-]+\.html$/i;
const MAX_REPLY_BYTES = 64 * 1024;
const TOOL_NAME = "show_html";
const FOCUS_POLL_MS = 1500;

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

function isPage(value: unknown): value is Page {
	const v = value as Partial<Page> | undefined;
	return typeof v?.path === "string" && typeof v?.title === "string";
}

// --- Reply server -----------------------------------------------------------

function replyScript(token: string): string {
	return `<script>window.pi={reply:function(text){return fetch("/pi-html/reply",{method:"POST",headers:{"content-type":"text/plain","x-pi-token":${JSON.stringify(token)}},body:String(text)}).then(function(r){if(!r.ok)throw new Error("pi did not accept the reply ("+r.status+")");});}};</script>`;
}

// After <head>, else after the doctype (a script before it forces quirks mode).
function withReplyScript(html: string, token: string): string {
	const script = replyScript(token);
	const head = html.match(/<head[^>]*>/i);
	if (head?.index !== undefined) {
		const at = head.index + head[0].length;
		return html.slice(0, at) + script + html.slice(at);
	}
	const doctype = html.match(/^\s*<!doctype[^>]*>/i);
	if (doctype) return doctype[0] + script + html.slice(doctype[0].length);
	return script + html;
}

class ReplyServer {
	private server?: Server;
	private port?: number;
	private readonly token = randomBytes(24).toString("hex");
	private readonly onReply: (text: string) => void;

	constructor(onReply: (text: string) => void) {
		this.onReply = onReply;
	}

	get running(): boolean {
		return this.port !== undefined;
	}

	urlFor(page: Page): string {
		return `http://127.0.0.1:${this.port}/pi-html/${basename(page.path)}`;
	}

	async start(): Promise<void> {
		if (this.server) return;
		const server = createServer((req, res) => {
			const url = new URL(req.url ?? "/", "http://127.0.0.1");
			if (req.method === "POST" && url.pathname === "/pi-html/reply") return this.reply(req, res);
			const name = url.pathname.startsWith("/pi-html/") ? url.pathname.slice("/pi-html/".length) : "";
			if (req.method !== "GET" || !PAGE_NAME.test(name)) return void res.writeHead(404).end();
			let html: string;
			try {
				html = readFileSync(join(PAGE_DIR, name), "utf8");
			} catch {
				return void res.writeHead(404).end();
			}
			res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
			res.end(withReplyScript(html, this.token));
		});
		this.server = server;
		await new Promise<void>((resolve, reject) => {
			server.once("error", reject);
			server.listen(0, "127.0.0.1", () => resolve());
		});
		server.unref();
		this.port = (server.address() as AddressInfo).port;
	}

	close(): void {
		this.server?.close();
		this.server = undefined;
		this.port = undefined;
	}

	private reply(req: import("node:http").IncomingMessage, res: import("node:http").ServerResponse): void {
		if (req.headers["x-pi-token"] !== this.token) return void res.writeHead(403).end();
		const chunks: Buffer[] = [];
		let size = 0;
		req.on("data", (chunk: Buffer) => {
			size += chunk.length;
			if (size > MAX_REPLY_BYTES) {
				res.writeHead(413).end();
				req.destroy();
				return;
			}
			chunks.push(chunk);
		});
		req.on("end", () => {
			if (res.writableEnded) return;
			const text = Buffer.concat(chunks).toString("utf8").trim();
			if (!text) return void res.writeHead(400).end();
			this.onReply(text);
			res.writeHead(204).end();
		});
	}
}

// --- Opening windows --------------------------------------------------------

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
function openUrl(url: string): Promise<void> {
	const [cmd, args] = openerFor(url);
	return new Promise((resolve, reject) => {
		const child = spawn(cmd, args, { detached: true, stdio: "ignore" });
		child.once("error", reject);
		child.once("spawn", () => {
			child.unref();
			resolve();
		});
	});
}

// --- Focus -------------------------------------------------------------------

function output(cmd: string, args: string[]): Promise<string> {
	return new Promise((resolve, reject) => {
		execFile(cmd, args, { timeout: 2000 }, (err, stdout) => (err ? reject(err) : resolve(stdout)));
	});
}

async function lookingAtThisAgent(): Promise<boolean> {
	const me = process.env.HC_TERMINAL_ID;
	if (!me) return true;
	try {
		if (process.env.NIRI_SOCKET) {
			const win = JSON.parse(await output("niri", ["msg", "-j", "focused-window"]));
			if (win?.app_id !== "herdr-app") return false;
		}
		const status = JSON.parse(await output("herdr-app", ["status"]));
		return status?.agent === me;
	} catch {
		return true;
	}
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
	let ctxRef: ExtensionContext | undefined;
	const server = new ReplyServer((text) => {
		// Typed as if by the person; queued behind a running turn.
		if (ctxRef && !ctxRef.isIdle()) pi.sendUserMessage(text, { deliverAs: "followUp" });
		else pi.sendUserMessage(text);
	});

	async function openPage(page: Page): Promise<void> {
		await server.start();
		await openUrl(server.urlFor(page));
	}

	// The newest page waiting for the person to look at this agent.
	let waiting: Page | undefined;
	let poll: ReturnType<typeof setInterval> | undefined;
	let checking = false;

	function stopWaiting(): void {
		if (poll) clearInterval(poll);
		poll = undefined;
		waiting = undefined;
	}

	function openWhenLooking(page: Page): void {
		waiting = page;
		if (poll) return;
		poll = setInterval(async () => {
			if (checking || !waiting) return;
			checking = true;
			try {
				if (!(await lookingAtThisAgent())) return;
				const next = waiting;
				stopWaiting();
				await openPage(next).catch((err) =>
					ctxRef?.ui.notify(`Could not open ${next.path}: ${(err as Error).message}`, "error"),
				);
			} finally {
				checking = false;
			}
		}, FOCUS_POLL_MS);
		poll.unref();
	}

	pi.on("session_start", async (_event, ctx) => {
		ctxRef = ctx;
	});
	pi.on("session_shutdown", async () => {
		stopWaiting();
		server.close();
	});

	pi.registerTool({
		name: TOOL_NAME,
		label: "Show HTML",
		description:
			"Open a self-contained HTML page for the user in a floating, interactive browser window. " +
			"Inline all CSS and JavaScript; only absolute https:// URLs load from the network. " +
			"The page can send the user's answer back to this chat with `await window.pi.reply(text)`; " +
			"the text arrives as the user's next message.",
		promptSnippet: "Show the user an interactive HTML page in a floating window; it can reply into the chat",
		promptGuidelines: [
			"Use show_html when the user asks for HTML, a visual, or something interactive, or when a diagram, chart, or interactive prototype explains the answer far better than text. Keep the chat reply short; do not repeat the page in prose.",
			"To ask the user something with show_html, give the page a submit control that calls `await window.pi.reply(text)` with a plain sentence of their answer, then shows that it was sent. End your turn and wait for the reply.",
		],
		parameters: Type.Object({
			title: Type.String({ description: "Short page title, also used in the file name" }),
			html: Type.String({ description: "The complete HTML document, starting with <!doctype html>" }),
		}),
		async execute(toolCallId, params, _signal, _onUpdate, ctx) {
			ctxRef = ctx;
			const page = savePage(params.title, params.html, toolCallId);
			if (await lookingAtThisAgent()) {
				stopWaiting();
				await openPage(page);
				return {
					content: [{ type: "text", text: `Opened "${page.title}" in a window for the user (${page.path}).` }],
					details: page,
				};
			}
			await server.start();
			openWhenLooking(page);
			const text = `The user is not looking at this agent; "${page.title}" opens when they come back (${page.path}).`;
			return { content: [{ type: "text", text }], details: page };
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
			const url = server.running ? server.urlFor(page) : pathToFileURL(page.path).href;
			text.setText(`${theme.fg("dim", hyperlink(page.path, url))}  ${theme.fg("muted", "/html to reopen")}`);
			return text;
		},
	});

	pi.registerCommand("html", {
		description: "Reopen the latest show_html page (/html list to pick one)",
		handler: async (args, ctx) => {
			ctxRef = ctx;
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
				if (waiting?.path === page.path) stopWaiting();
				await openPage(page);
			} catch (err) {
				ctx.ui.notify(`Could not open ${page.path}: ${(err as Error).message}`, "error");
			}
		},
	});
}
