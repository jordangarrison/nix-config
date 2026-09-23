{
  buildNpmPackage,
  lib,
}:

# Only packages/omp-plugins consumes this bundle now: pi installs its own
# extensions (unversioned, latest) from programs.pi.settings.packages. OMP needs
# pi-claude-bridge plus its resolved dependency graph, which this build keeps.
# The other dependencies in package.json are dead weight left in place to avoid
# a lockfile refresh; nothing loads them. This whole package is deleted once
# ~/dev/jordangarrison/pi-extensions ships an omp-native bridge, so do not
# grow it.
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
  # @earendil-works/pi-coding-agent (the pi npm package) ships an npm-shrinkwrap.json whose five
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
  npmDepsHash = "sha256-pNRs+YOmEHHv4yZuUWHr90/upb+YhIE01vOYHobHTIQ=";

  dontNpmBuild = true;
  dontNpmPrune = true;
  npmInstallFlags = [
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];
  npmPackFlags = [ "--ignore-scripts" ];

  # Claude Bridge always uses the separately Nix-managed Claude Code binary,
  # so omit the Agent SDK's redundant 220+ MiB platform binary from the result.
  postInstall = ''
    rm -rf "$out/lib/node_modules/jordangarrison-pi-extensions/node_modules/@anthropic-ai"/claude-agent-sdk-{darwin,linux,win32}-*
  '';

  meta = {
    description = "pi-claude-bridge dependency graph for the OMP plugin bundle";
    license = lib.licenses.mit;
  };
}
