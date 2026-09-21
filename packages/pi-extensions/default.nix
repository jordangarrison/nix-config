{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  pi,
}:

let
  # Keep the released package in package-lock.json for its dependency graph,
  # then replace its source with the matching release tag from GitHub. The npm
  # tarball omits CHANGELOG.md, which postInstall copies alongside the source,
  # and a tag pin makes a later move to an unreleased revision a one-line change.
  pi-claude-bridge = fetchFromGitHub {
    owner = "elidickinson";
    repo = "pi-claude-bridge";
    rev = "d3cb25e96742c47e77675ba7ff50e181ebb476ef"; # v0.8.0
    hash = "sha256-/7Ofo9nt74RXaV+01TIzguFxm0FpeNKRXV5Uk67qSGI=";
  };

  # pi-until is not published to npm, and its committed package-lock.json has
  # entries missing `integrity`, which makes nixpkgs' prefetch-npm-deps panic on
  # a `github:` dependency. So vendor the source directly and let the bundle's
  # own lockfile carry the one runtime dependency that needs carrying (xstate).
  # Its other declared dependency (@earendil-works/pi-tui) and the rest of what
  # it imports (@earendil-works/*, typebox) are injected by pi at load time.
  pi-until = fetchFromGitHub {
    owner = "joelhooks";
    repo = "pi-until";
    rev = "7c90bdc90291321f60130984e479bc4a844a7d50"; # main @ 2026-08-19
    hash = "sha256-/nOVWOS5uf0qqiap23nlrAqS02T5y5yAcqkA+5eU/7o=";
  };

  # Single source of truth for the bundled pi library version: the package.json
  # pin, which npm ci requires package-lock.json to agree with.
  pinnedPiVersion = (lib.importJSON ./package.json).dependencies."@earendil-works/pi-coding-agent";
in
# The async runner points background children at the copy of the pi library
# bundled here (see the JITI_ALIAS/PI_PACKAGE_DIR notes in postInstall), while
# the parent session runs the standalone binary from the llm-agents flake. Those
# two have to be the same pi, or a routine `nh flake update llm-agents` silently
# leaves every background child on a different pi version than its parent. PR CI
# is eval-only (docs/adr/005-pr-ci-nix-validation.md), so this assertion is what
# makes that drift fail the nightly flake-update PR instead of merging unnoticed.
assert lib.assertMsg (pi.version == pinnedPiVersion) ''
  pi-extensions bundles @earendil-works/pi-coding-agent ${pinnedPiVersion}, but the
  installed pi (pkgs.llm-agents.pi) is ${pi.version}, so background subagents would
  run a different pi than their parent session.

  To fix: set the "@earendil-works/pi-coding-agent" pin in
  packages/pi-extensions/package.json to ${pi.version}, refresh package-lock.json
  per the comment above npmDepsHash in packages/pi-extensions/default.nix, and
  recompute npmDepsHash.
'';
buildNpmPackage {
  pname = "jordangarrison-pi-extensions";
  version = "1.5.0";

  src = ./.;
  # Refresh with `npm install --package-lock-only --ignore-scripts --legacy-peer-deps`,
  # then apply both lockfile fix-ups described below — npm regenerates the file
  # without them, and the result breaks the build (`prefetch-npm-deps` panics on
  # fix-up 1's absence; `npm ci` then hits ENOTCACHED without fix-up 2) — and only
  # then recompute using `nix run nixpkgs#prefetch-npm-deps -- package-lock.json`.
  #
  # @earendil-works/pi-coding-agent (the pi npm package, which pi-subagents needs
  # in order to spawn background children) ships an npm-shrinkwrap.json whose five
  # @earendil-works/* entries have no `integrity`, even though the tarball itself
  # carries no node_modules. npm re-inflates that shrinkwrap into our lockfile,
  # integrity-less entries and all, which makes prefetch-npm-deps panic, and then
  # refetches those five tarballs by URL alone at install time — an integrity-less
  # fetch goes through npm's HTTP cache, which always misses in the sandbox, so
  # `npm ci` dies with ENOTCACHED. (The `inBundle` markers on that subtree come
  # from this package's own `bundledDependencies` below; upstream declares none.)
  # So after every `npm install --package-lock-only`, fix up package-lock.json:
  #
  #   1. add `integrity` (from `npm view <pkg>@<version> dist.integrity`) to the five
  #      `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/*`
  #      entries — the ~160 other nested entries already carry it from npm, and
  #   2. drop `"hasShrinkwrap": true` from the
  #      `node_modules/@earendil-works/pi-coding-agent` entry, so npm installs the
  #      subtree our lockfile pins (with integrity, served from the Nix-prefetched
  #      cache) instead of re-inflating upstream's shrinkwrap over it.
  npmDepsHash = "sha256-47sAYhQMrqAU4ryjWN1+xENxfKeist1+clkuKSIot64=";

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
    # the footer silently stops warning that the premium-cost tier is active
    # (upstream bills fast mode at 2.5x for gpt-5.5, 2x otherwise).
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
