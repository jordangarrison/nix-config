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

    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/index.ts" \
      --replace-fail \
        'import { buildSessionContext, compact, generateBranchSummary, keyHint, type BranchSummaryResult, type CompactionEntry, type ExtensionAPI, type ExtensionContext, type ExtensionUIContext } from "@earendil-works/pi-coding-agent";' \
        'import { buildSessionContext, compact, keyText, type CompactionEntry, type ExtensionAPI, type ExtensionContext, type ExtensionUIContext } from "@earendil-works/pi-coding-agent"; import { generateBranchSummary, type BranchSummaryResult } from "@oh-my-pi/pi-agent-core/compaction/branch-summarization";' \
      --replace-fail \
        'keyHint("app.tools.expand", "to expand")' \
        '`''${keyText("app.tools.expand")} to expand`'

    substituteInPlace "$plugins/node_modules/pi-claude-bridge/src/index.ts" \
      --replace-fail \
        '// Subsequent instance (subagent session): skip registration entirely.' \
        '// OMP gives child sessions a distinct model registry, so register the provider there too.
        pi.registerProvider(PROVIDER_ID, {
          baseUrl: "claude-bridge",
          apiKey: "not-used",
          api: "claude-bridge",
          models: registeredModels,
          streamSimple: g[ACTIVE_STREAM_SIMPLE_KEY] as any,
        });' \
      --replace-fail \
        '// The subagent already has access to claude-bridge models via the shared' \
        '// Reuse the parent stream function so tool-result routing retains its state.' \
      --replace-fail \
        "// ModelRegistry from the parent's registration. Calls to those models" \
        "// Re-registering also installs the provider's dummy credential in the child registry." \
      --replace-fail \
        "// route through the parent's streamSimple via reentrant QueryContexts." \
        "// The registration is idempotent when a Pi child shares the parent registry."

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
