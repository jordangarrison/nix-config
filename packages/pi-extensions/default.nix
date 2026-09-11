{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
}:

let
  # npm's latest release does not yet include Fable 5.1 support. Keep the
  # released package in package-lock.json for its dependency graph, then replace
  # its source with a reproducibly pinned revision from upstream's main branch.
  pi-claude-bridge = fetchFromGitHub {
    owner = "elidickinson";
    repo = "pi-claude-bridge";
    rev = "4a7920ac4f4449b546307b3a53d4a4867f8b6cb5"; # main @ 2026-09-09
    hash = "sha256-dZEbRahk9Eu6mieVn+Zn5OZDvHRrcuMfsy5Kxa5aHIg=";
  };

  # pi-until is not published to npm, and its committed package-lock.json has
  # entries missing `integrity`, which makes nixpkgs' prefetch-npm-deps panic on
  # a `github:` dependency. So vendor the source directly and let the bundle's
  # own lockfile carry its one runtime dependency (xstate). Everything else it
  # imports (@earendil-works/*, typebox) is injected by pi at load time.
  pi-until = fetchFromGitHub {
    owner = "joelhooks";
    repo = "pi-until";
    rev = "7c90bdc90291321f60130984e479bc4a844a7d50"; # main @ 2026-08-19
    hash = "sha256-/nOVWOS5uf0qqiap23nlrAqS02T5y5yAcqkA+5eU/7o=";
  };
in
buildNpmPackage {
  pname = "jordangarrison-pi-extensions";
  version = "1.5.0";

  src = ./.;
  # Refresh with `npm install --package-lock-only --ignore-scripts --legacy-peer-deps`,
  # then recompute using `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  #
  # @earendil-works/pi-coding-agent (the pi npm package, which pi-subagents needs
  # in order to spawn background children) ships an npm-shrinkwrap.json whose five
  # @earendil-works/* entries have no `integrity`, and its tarball does not
  # actually contain the `node_modules` its `bundleDependencies` claims. npm
  # copies those integrity-less entries into our lockfile, which makes
  # prefetch-npm-deps panic, and then refetches those five tarballs by URL alone
  # at install time — an integrity-less fetch goes through npm's HTTP cache, which
  # always misses in the sandbox, so `npm ci` dies with ENOTCACHED. So after every
  # `npm install --package-lock-only`, fix up package-lock.json:
  #
  #   1. add `integrity` (from `npm view <pkg>@<version> dist.integrity`) to every
  #      `node_modules/@earendil-works/pi-coding-agent/node_modules/*` entry, and
  #   2. drop `"hasShrinkwrap": true` from the
  #      `node_modules/@earendil-works/pi-coding-agent` entry, so npm installs the
  #      subtree our lockfile pins (with integrity, served from the Nix-prefetched
  #      cache) instead of re-inflating upstream's shrinkwrap over it.
  npmDepsHash = "sha256-iBUG7yDZC3KzZPlgk7MwecI8WLF0AhxYJoJgvWd2mrc=";

  dontNpmBuild = true;
  dontNpmPrune = true;
  npmInstallFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  npmPackFlags = [ "--ignore-scripts" ];

  postInstall = ''
    bundle="$out/lib/node_modules/jordangarrison-pi-extensions"
    piUsage="$bundle/node_modules/@narumitw/pi-usage/src"

    # Replace the npm release's source while retaining its already-resolved,
    # API-compatible dependency graph.
    rm -rf "$bundle/node_modules/pi-claude-bridge"
    mkdir -p "$bundle/node_modules/pi-claude-bridge"
    cp -r ${pi-claude-bridge}/src ${pi-claude-bridge}/package.json \
      ${pi-claude-bridge}/README.md ${pi-claude-bridge}/CHANGELOG.md ${pi-claude-bridge}/LICENSE \
      "$bundle/node_modules/pi-claude-bridge/"

    # Drop the vendored pi-until where its manifest entry expects it. Its
    # `import "xstate"` resolves by walking up to the bundle's flat node_modules,
    # the same way every npm-installed extension here resolves its deps.
    mkdir -p "$bundle/node_modules/@joelhooks/pi-until"
    cp -r ${pi-until}/extensions ${pi-until}/src ${pi-until}/package.json ${pi-until}/LICENSE \
      "$bundle/node_modules/@joelhooks/pi-until/"
    chmod -R u+w "$bundle/node_modules/@joelhooks/pi-until"

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

    # pi's Nix wrapper exports PI_PACKAGE_DIR pointing at the standalone binary's
    # directory, whose layout (theme/, assets/ at the top level, no dist/) only
    # makes sense for that bun-compiled binary. The async runner is a plain Node
    # process that loads the pi library out of the npm package bundled here,
    # where those assets live under dist/ - so it must not inherit the parent's
    # PI_PACKAGE_DIR, or every background child dies on a missing dark.json.
    # Point it at the package the child actually runs.
    substituteInPlace "$bundle/node_modules/pi-subagents/src/runs/background/async-execution.ts" \
      --replace-fail \
        '[JITI_ALIAS_ENV]: JSON.stringify(hostPeerAliases.aliases),' \
        '[JITI_ALIAS_ENV]: JSON.stringify(hostPeerAliases.aliases), PI_PACKAGE_DIR: piPackageRoot,'

    # Claude Bridge always uses the separately Nix-managed Claude Code binary,
    # so omit the Agent SDK's redundant 220+ MiB platform binary from the result.
    rm -rf "$bundle/node_modules/@anthropic-ai"/claude-agent-sdk-{darwin,linux,win32}-*

    unset bundle piUsage
  '';

  meta = {
    description = "Reproducible bundle of Pi extensions managed by Nix";
    license = lib.licenses.mit;
  };
}
