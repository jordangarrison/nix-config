import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  let turnCount = 0;

  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    ctx.ui.setStatus("jordangarrison-status", ctx.ui.theme.fg("dim", "pi ready"));
  });

  pi.on("turn_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    turnCount += 1;
    const marker = ctx.ui.theme.fg("accent", "●");
    const label = ctx.ui.theme.fg("dim", ` turn ${turnCount}`);
    ctx.ui.setStatus("jordangarrison-status", `${marker}${label}`);
  });

  pi.on("turn_end", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    const marker = ctx.ui.theme.fg("success", "✓");
    const label = ctx.ui.theme.fg("dim", ` turn ${turnCount} complete`);
    ctx.ui.setStatus("jordangarrison-status", `${marker}${label}`);
  });
}
