{
  buildNpmPackage,
  lib,
}:

buildNpmPackage {
  pname = "jordangarrison-pi-extensions";
  version = "1.2.0";

  src = ./.;
  # Refresh with `npm install --package-lock-only --ignore-scripts --legacy-peer-deps`,
  # then recompute using `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  npmDepsHash = "sha256-X0VIA9KoWMQI9Zve8c5ZyOsfG2TkEhZJQlZpiIU9j3w=";

  dontNpmBuild = true;
  dontNpmPrune = true;
  npmInstallFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  npmPackFlags = [ "--ignore-scripts" ];

  postInstall = ''
    piUsage="$out/lib/node_modules/jordangarrison-pi-extensions/node_modules/@narumitw/pi-usage/src"

    # Match the compact footer used by the Claude subscription extension:
    # "[usage] 5h:12% 7d:26%" reporting consumption, not upstream's unlabeled
    # remaining quota ("codex 88% wk").
    substituteInPlace "$piUsage/format.ts" \
      --replace-fail \
        'group === "codex" ? "codex" : `codex ''${compactLimitLabel(labelBucket?.groupLabel ?? group)}`,' \
        'group === "codex" ? "[usage]" : `[usage] ''${compactLimitLabel(labelBucket?.groupLabel ?? group)}`,' \
      --replace-fail \
        '`''${clampPercent(bucket.remaining).toFixed(0)}% ''${formatWindowLabel(bucket.windowMinutes, fallback, true)}`,' \
        '`''${formatWindowLabel(bucket.windowMinutes, fallback, true)}:''${(100 - clampPercent(bucket.remaining)).toFixed(0)}%`,' \
      --replace-fail \
        'return compact && fallback === "weekly" ? "wk" : capitalize(fallback);' \
        'return compact && fallback === "weekly" ? "7d" : capitalize(fallback);' \
      --replace-fail \
        'if (minutes === 10_080) return compact ? "wk" : "Weekly";' \
        'if (minutes === 10_080) return compact ? "7d" : "Weekly";'

    # The fast-mode marker anchors on the old "codex" prefix, so re-anchor it or
    # the footer silently stops warning that the 2x-cost tier is active.
    substituteInPlace "$piUsage/codex-fast.ts" \
      --replace-fail \
        'if (!enabled || !/^codex(?:\s|$)/u.test(status)) return status;' \
        'if (!enabled || !/^\[usage\](?:\s|$)/u.test(status)) return status;' \
      --replace-fail \
        'return status === "codex" ? "codex fast" : `codex fast''${status.slice("codex".length)}`;' \
        'return status === "[usage]" ? "[usage] fast" : `[usage] fast''${status.slice("[usage]".length)}`;'

    # Pi sorts footer statuses by key, so "0-usage" keeps the segment leftmost,
    # matching the Claude extension's sibling key "0-usage-claude".
    #
    # Upstream also emits an uncolored status string. Dim the labels and color
    # each percentage by its own severity, so one hot window stands out. Only
    # "label:NN%" tokens are colored: those are the ones the format patch above
    # converted to consumption, whereas other providers (GitHub Copilot) still
    # report remaining quota, which this scale would invert.
    substituteInPlace "$piUsage/usage.ts" \
      --replace-fail \
        'const STATUS_KEY = "usage";' \
        'const STATUS_KEY = "0-usage";' \
      --replace-fail \
        'ctx.ui.setStatus(STATUS_KEY, value);' \
        'ctx.ui.setStatus(STATUS_KEY, value === undefined ? undefined : value.split(" ").map((token) => { const match = /^(.*?:)(\d+)%$/.exec(token); if (!match) return ctx.ui.theme.fg("dim", token); const percent = Number(match[2]); return ctx.ui.theme.fg("dim", match[1]) + ctx.ui.theme.fg(percent >= 90 ? "error" : percent >= 70 ? "warning" : "success", match[2] + "%"); }).join(" "));'

    # Claude Bridge always uses the separately Nix-managed Claude Code binary,
    # so omit the Agent SDK's redundant 220+ MiB platform binary from the result.
    rm -rf "$out/lib/node_modules/jordangarrison-pi-extensions/node_modules/@anthropic-ai"/claude-agent-sdk-{darwin,linux,win32}-*

    unset piUsage
  '';

  meta = {
    description = "Reproducible bundle of Pi extensions managed by Nix";
    license = lib.licenses.mit;
  };
}
