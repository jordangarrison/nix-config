{
  lib,
  runCommand,
  piExtensions,
}:

let
  piBundle = "${piExtensions}/lib/node_modules/jordangarrison-pi-extensions";
  packageManifest = builtins.toJSON {
    name = "jordangarrison-omp-plugins";
    version = "1.0.0";
    private = true;
    omp.extensions = [ "./node_modules/pi-claude-bridge/src/index.ts" ];
  };
in
runCommand "jordangarrison-omp-plugins-1.0.0"
  {
    meta = {
      description = "Reproducible OMP-compatible extension bundle";
      license = lib.licenses.mit;
    };
  }
  ''
    plugins="$out/lib/node_modules/jordangarrison-omp-plugins"
    mkdir -p "$plugins/node_modules"

    # Reuse the pinned dependency graph from the Pi bundle without copying it.
    # Claude Bridge itself is copied because OMP needs narrow compatibility patches.
    for dependency in ${piBundle}/node_modules/*; do
      ln -s "$dependency" "$plugins/node_modules/$(basename "$dependency")"
    done
    rm -rf "$plugins/node_modules/pi-claude-bridge"
    cp -r ${piBundle}/node_modules/pi-claude-bridge "$plugins/node_modules/pi-claude-bridge"
    chmod -R u+w "$plugins/node_modules/pi-claude-bridge"
    patch -d "$plugins/node_modules/pi-claude-bridge" -p1 < ${./omp-prompt-array.patch}

    # The bridge only sends `<id>[1m]` for ids in MEASURED_ONE_M, so
    # claude-opus-5-5 would register at 200K. Treat it like claude-opus-5
    # until upstream adds it.
    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/models.ts" \
      --replace-fail \
        '"claude-opus-5",' \
        '"claude-opus-5", "claude-opus-5-5",'

    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/index.ts" \
      --replace-fail \
        'import { buildSessionContext, compact, generateBranchSummary, keyHint, type BranchSummaryResult, type CompactionEntry, type ExtensionAPI, type ExtensionContext, type ExtensionUIContext } from "@earendil-works/pi-coding-agent";' \
        'import { buildSessionContext, compact, keyText, type CompactionEntry, type ExtensionAPI, type ExtensionContext, type ExtensionUIContext } from "@earendil-works/pi-coding-agent"; import { generateBranchSummary, type BranchSummaryResult } from "@oh-my-pi/pi-agent-core/compaction/branch-summarization";' \
      --replace-fail \
        'keyHint("app.tools.expand", "to expand")' \
        '`''${keyText("app.tools.expand")} to expand`'

    # A later module instance is an OMP child session (task tool). OMP gives it a
    # distinct model registry and runs its first query before session_start, so
    # the upstream deferral leaves the child with "No API key found for
    # claude-bridge". Register at load instead, reusing the parent's stream
    # function so tool-result routing keeps its state.
    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/index.ts" \
      --replace-fail \
        '		debug(`provider: deferring registration decision to session_start (module=''${moduleInstanceId})`);
		pi.on("session_start", (_event, ctx) => {
			if (ctx.modelRegistry.getProvider(PROVIDER_ID)) {
				debug(`provider: registry already has ''${PROVIDER_ID}, skipping registration (module=''${moduleInstanceId})`);
				return;
			}
			debug(`provider: registry lacks ''${PROVIDER_ID}, registering (module=''${moduleInstanceId})`);
			pi.registerProvider(PROVIDER_ID, providerConfig);
		});' \
        '		pi.registerProvider(PROVIDER_ID, { ...providerConfig, streamSimple: g[ACTIVE_STREAM_SIMPLE_KEY] as any });
		debug(`provider: registered into child registry with the parent stream function (module=''${moduleInstanceId})`);'

    # OMP emits session_start only with reason "startup" or "reload". /new, /fork
    # and /resume arrive as session_switch instead, which upstream Pi never sends.
    # Without a session_switch handler the bridge keeps the previous
    # conversation's Claude Code session and cursor. Every turn of the new
    # conversation then looks like a "shorter context", takes the clean-start
    # path with no history, and deletes its own Claude Code session afterward.
    # Only the shared session is reset here: the global streamSimple key must
    # survive a switch because OMP child sessions register the provider from it.
    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/index.ts" \
      --replace-fail \
        '	pi.on("session_shutdown", () => {
		reportLeaks("session_shutdown");
		clearSession("session_shutdown");
	});' \
        '	pi.on("session_shutdown", () => {
		reportLeaks("session_shutdown");
		clearSession("session_shutdown");
	});
	(pi as any).on("session_switch", (event: { reason?: string }) => {
		debug(`session_switch:''${event?.reason ?? "unknown"}: clearing session ''${sharedSession?.sessionId?.slice(0, 8) ?? "none"}`);
		sharedSession = null;
	});'

    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/skills.ts" \
      --replace-fail \
        'import { formatSkillsForPrompt, type Skill } from "@earendil-works/pi-coding-agent";' \
        'import type { Skill } from "@earendil-works/pi-coding-agent";'

    cat >> "$plugins/node_modules/pi-claude-bridge/src/skills.ts" <<'EOF'

// OMP's legacy Pi compatibility barrel does not export formatSkillsForPrompt.
// Keep the Agent Skills wire format local so this extension does not depend on
// that non-runtime helper being part of OMP's compatibility surface.
function formatSkillsForPrompt(skills: Skill[]): string {
	const visibleSkills = skills.filter((skill) => !skill.disableModelInvocation);
	if (visibleSkills.length === 0) return "";

	const lines = [
		"\\n\\nThe following skills provide specialized instructions for specific tasks.",
		"Use the read tool to load a skill's file when the task matches its description.",
		"When a skill file references a relative path, resolve it against the skill directory (parent of SKILL.md / dirname of the path) and use that absolute path in tool commands.",
		"",
		"<available_skills>",
	];
	for (const skill of visibleSkills) {
		lines.push("  <skill>");
		lines.push(`    <name>''${escapeXml(skill.name)}</name>`);
		lines.push(`    <description>''${escapeXml(skill.description)}</description>`);
		lines.push(`    <location>''${escapeXml(skill.filePath)}</location>`);
		lines.push("  </skill>");
	}
	lines.push("</available_skills>");
	return lines.join("\\n");
}

function escapeXml(value: string): string {
	return value
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/\"/g, "&quot;")
		.replace(/'/g, "&apos;");
}
EOF

    cat > "$plugins/package.json" <<'EOF'
${packageManifest}
EOF
  ''
