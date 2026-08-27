{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  jq,
  curl,
  bun,
  pi,
  gws,
  gh,
  fraunces,
}:

# day-dashboard ships a bash orchestrator plus a Node renderer + collectors +
# prompt. It is not a single-file script, so it uses its own derivation rather
# than lib/mkScript.nix. The entrypoint is wrapped with exactly the runtime
# deps it shells out to (pi drives the Slack/Linear MCP servers and the
# synthesis model, gws reads Gmail/Calendar, bun renders, jq/curl for the
# Confluence collector) so it is hermetic under systemd's minimal PATH.
stdenvNoCC.mkDerivation {
  pname = "day-dashboard";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  # Fail the build if the renderer's unit tests regress. This is the security
  # gate (injection-safety) baked into the package.
  doCheck = true;
  nativeCheckInputs = [ bun ];
  checkPhase = ''
    runHook preCheck
    bun test test/render.test.mjs
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/day-dashboard"
    cp lib/collect.sh lib/render.mjs lib/prompt.md lib/dismiss-server.mjs \
      "$out/libexec/day-dashboard/"

    # Fraunces (compact ~64KB static TTF) is base64-embedded into the page for
    # the serif headline — no network, self-contained, works over file:// too.
    cp ${fraunces}/share/fonts/truetype/Fraunces9pt-SemiBold.ttf \
      "$out/libexec/day-dashboard/headline.ttf"

    install -Dm755 day-dashboard.sh "$out/bin/day-dashboard"
    wrapProgram "$out/bin/day-dashboard" \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils jq curl bun pi gws gh ]}

    # Companion HTTP handler for the ✕ dismiss links (see the home module). Its
    # LIBDIR is pinned to this store libexec so it finds render.mjs + the font;
    # the state dir + port come from the service environment.
    makeWrapper ${bun}/bin/bun "$out/bin/day-dashboard-dismiss-server" \
      --add-flags "$out/libexec/day-dashboard/dismiss-server.mjs" \
      --set DAY_DASHBOARD_LIBDIR "$out/libexec/day-dashboard"

    runHook postInstall
  '';

  meta = {
    description = "Hourly private personal day/work dashboard rendered from calendar/email/Slack/Linear/Confluence via the Pi CLI + MCP + gws";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "day-dashboard";
  };
}
