{
  config,
  lib,
  pkgs,
  userApps ? { },
  ...
}:

let
  stateDir = "${config.xdg.configHome}/ovis";
  tokenFile = "${stateDir}/token.env";
  # Bundle the unmodified upstream extension from the same source as the server.
  # The published package does not install integrations/. This is the installer's
  # node/ESM build, kept in the store rather than written into Pi at runtime.
  piIntegration = pkgs.runCommand "ovis-pi-integration-${pkgs.llm-agents.ovis.version}" {
    nativeBuildInputs = [ pkgs.bun ];
  } ''
    mkdir -p "$out"
    bun build ${pkgs.llm-agents.ovis.src}/integrations/pi-ask.ts \
      --target=node --format=esm --outfile="$out/herdr-web-ui.js"
  '';
  # A missing or empty token must never expose the terminals through nginx.
  checkToken = pkgs.writeShellScript "ovis-check-token" ''
    if [ -z "''${OVIS_TOKEN:-}" ]; then
      echo "Ovis requires OVIS_TOKEN in ${tokenFile}" >&2
      exit 1
    fi
  '';
in
{
  config = lib.mkIf (userApps.ovis.enable or false) {
    home.packages = [ pkgs.llm-agents.ovis ];

    programs.pi.extensions.files."herdr-web-ui.js" = lib.mkIf config.programs.pi.enable {
      source = "${piIntegration}/herdr-web-ui.js";
    };

    systemd.user.services.ovis = {
      Unit.Description = "Ovis browser and phone client for herdr-core";
      Install.WantedBy = [ "default.target" ];
      Service = {
        ExecStartPre = toString checkToken;
        ExecStart = lib.getExe pkgs.llm-agents.ovis;
        WorkingDirectory = config.home.homeDirectory;
        # Required, not prefixed with "-": credentials stay outside the store.
        EnvironmentFile = tokenFile;
        Environment = [
          "HOST=127.0.0.1"
          "PORT=7317"
          "OVIS_RUNTIME=herdr-core"
          # ADR 007: hc is self-managed, never supplied by Nix.
          "OVIS_HC_BIN=${config.home.homeDirectory}/.local/bin/hc"
          "OVIS_STATE_DIR=${stateDir}"
          "OVIS_TELEMETRY=0"
          # The new-session picker needs the same agent CLIs as the user.
          "PATH=${config.home.homeDirectory}/.local/bin:${config.home.profileDirectory}/bin:/run/wrappers/bin:/run/current-system/sw/bin"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
      };
    };
  };
}
