import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const protectedPathSegments = new Set([".git", "node_modules", ".direnv"]);
const protectedBasenames = new Set(["result", "result-1", "result-2"]);

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/");
}

function basename(path: string): string {
  const normalized = normalizePath(path).replace(/\/+$/, "");
  const parts = normalized.split("/").filter(Boolean);
  return parts[parts.length - 1] ?? normalized;
}

function isEnvFile(path: string): boolean {
  const name = basename(path);
  return name === ".env" || name.startsWith(".env.");
}

function hasProtectedSegment(path: string): boolean {
  const segments = normalizePath(path).split("/").filter(Boolean);
  return segments.some((segment) => protectedPathSegments.has(segment));
}

function isProtectedPath(path: string): boolean {
  return isEnvFile(path) || hasProtectedSegment(path) || protectedBasenames.has(basename(path));
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") {
      return undefined;
    }

    const path = event.input.path;
    if (typeof path !== "string") {
      return undefined;
    }

    if (!isProtectedPath(path)) {
      return undefined;
    }

    if (ctx.hasUI) {
      ctx.ui.notify(`Blocked ${event.toolName} to protected path: ${path}`, "warning");
    }

    return {
      block: true,
      reason: `Path "${path}" is protected by the protected-paths extension`,
    };
  });
}
