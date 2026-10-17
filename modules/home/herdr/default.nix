{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.herdr;
  collie = cfg.collie;
  tomlFormat = pkgs.formats.toml { };

  collieRoot = "${collie.package}/lib/collie";

  # Collie reads <config-dir>/config.toml as its instance layer. Writing the
  # settings here, not into the unit's environment, means the service and
  # interactive verbs (`collie pair`, `collie devices`, `collie doctor`) see the
  # same values. Precedence: this file < process env < ~/.config/collie/.env.
  collieConfig = tomlFormat.generate "collie-config.toml" (
    recursiveUpdate (
      {
        network = {
          inherit (collie) host port;
        }
        // optionalAttrs (collie.tailscaleHosts != [ ]) {
          tailscale_hosts = collie.tailscaleHosts;
        }
        // optionalAttrs (collie.publicUrl != null) {
          public_url = collie.publicUrl;
        };
        serve.serve_port = collie.tailscaleServe.port;
      }
      // optionalAttrs (collie.trustedUser != null) {
        access.trusted_user = collie.trustedUser;
      }
    ) collie.settings
  );

  tailscale = getExe' pkgs.tailscale "tailscale";
in
{
  # Keep our llm-agents package and activation-time integration ownership.
  disabledModules = [ "programs/herdr.nix" ];

  options.programs.herdr = {
    enable = mkEnableOption "herdr terminal workspace manager for AI coding agents";

    package = mkOption {
      type = types.package;
      default = pkgs.llm-agents.herdr;
      defaultText = literalExpression "pkgs.llm-agents.herdr";
      description = "The herdr package to install.";
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      example = literalExpression ''
        {
          onboarding = false;
          theme.name = "rose-pine";
          experimental.pane_history = true;
          session.resume_agents_on_restore = true;
        }
      '';
      description = ''
        Settings written to {file}`$XDG_CONFIG_HOME/herdr/config.toml`.

        Because Nix manages this file it becomes a read-only symlink: change
        settings here and rebuild rather than editing them in the herdr UI.
        herdr's mutable runtime state (session.json, session-history.json,
        logs, sockets, release-notes.json) is intentionally not managed and
        stays writable.
      '';
    };

    integrations = mkOption {
      type = types.listOf (types.enum [
        "pi"
        "omp"
        "claude"
        "codex"
        "opencode"
        "hermes"
        "qodercli"
      ]);
      default = [ ];
      example = [
        "claude"
        "codex"
      ];
      description = ''
        herdr agent integrations to install and keep current on every
        activation, via `herdr integration install <name>`.

        herdr installs these hooks into per-agent dotfiles (e.g.
        {file}`~/.claude/hooks/herdr-agent-state.sh`) and bumps their version
        with each herdr release. The hooks record the agent's native session
        id, which is what `session.resume_agents_on_restore` needs to resume a
        conversation after a server restart. Re-running the installer on every
        rebuild keeps the hooks in sync with the installed herdr version, so
        agent-session resume keeps working across herdr updates instead of
        silently breaking when the integration version drifts.

        These hooks live in mutable dotfiles outside the Nix store (that is how
        herdr ships them); this option only keeps them current, it does not
        manage their contents declaratively.
      '';
    };

    # Collie is remote shell access by design: a paired device can read every
    # pane and type into it as you. The bridge binds loopback only and is
    # published to the tailnet by `tailscale serve`, never `funnel`. Pair a
    # device with `collie pair` before opening the URL; until then every
    # request gets `403 device not paired`.
    collie = {
      enable = mkEnableOption "Collie (ColliePWA), a self-hosted phone web UI for the agents in herdr";

      package = mkOption {
        type = types.package;
        default = pkgs.callPackage ../../../packages/collie { };
        defaultText = literalExpression "pkgs.callPackage ../../../packages/collie { }";
        description = "The Collie package to run.";
      };

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = ''
          Address the bridge binds. Collie refuses a non-loopback bind unless
          `settings.network.allow_non_loopback_bind = true`; keep loopback and
          let `tailscale serve` be the only way in.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 8787;
        description = "Loopback port the bridge listens on.";
      };

      trustedUser = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "you@example.com";
        description = ''
          Tailscale login every request must carry in the
          `Tailscale-User-Login` header that `tailscale serve` injects. Other
          tailnet users, and tagged nodes (which get no header), are refused.
        '';
      };

      tailscaleHosts = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "myhost.tail1234.ts.net" ];
        description = ''
          Host-header allowlist for the bridge. Empty means Collie discovers
          the MagicDNS name and tailnet IPs with `tailscale status` at start.
          The gate fails closed, so if that discovery fails (tailscaled not up
          yet) the bridge refuses every request until restarted; pinning the
          name here removes that race.
        '';
      };

      publicUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://myhost.tail1234.ts.net:8443";
        description = ''
          The URL phones open. Collie uses it for `collie url`, `collie qr`
          and the pairing QR, since this module, not Collie, publishes the
          front door.
        '';
      };

      tailscaleServe = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Publish the bridge on the tailnet with `tailscale serve` (HTTPS,
            tailnet-only) from a user oneshot, and remove the mapping when the
            service stops. Requires this user to be the tailscaled operator
            (`tailscale set --operator=<user>`, e.g. via the NixOS option
            `services.tailscale.extraSetFlags`).
          '';
        };

        port = mkOption {
          type = types.port;
          default = 8443;
          description = ''
            Tailnet HTTPS port. Not 443: `tailscale serve` on 443 intercepts
            all tailnet traffic to that port, shadowing any web server (e.g.
            nginx) that already answers on the node's tailnet IP.
          '';
        };
      };

      settings = mkOption {
        type = tomlFormat.type;
        default = { };
        example = literalExpression ''
          {
            bridge.transcript = true;
            phone.run = false;
          }
        '';
        description = ''
          Extra Collie settings merged into
          {file}`$XDG_CONFIG_HOME/collie/config.toml` (see `collie config init
          --print` for every key). Put secrets such as push VAPID keys in
          {file}`~/.config/collie/.env` (mode 600) instead; `collie push-keys`
          writes there.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !collie.enable || pkgs.stdenv.hostPlatform.isLinux;
        message = "programs.herdr.collie is wired as a systemd user service and supports Linux only.";
      }
    ];

    home.packages = [
      cfg.package
      pkgs.herdr-handoff
    ]
    ++ optional collie.enable collie.package;

    xdg.configFile."collie/config.toml" = mkIf collie.enable {
      source = collieConfig;
    };

    # Mirrors upstream's systemd/collie.service. Named `collie` so the CLI's
    # `collie status` and `collie logs` find it. Manage it with systemctl, not
    # `collie start`/`stop`, which would try to write their own unit.
    systemd.user.services.collie = mkIf collie.enable {
      Unit = {
        Description = "Collie: phone web UI for herdr";
        # A phone-only operator can't run `systemctl reset-failed`.
        StartLimitIntervalSec = 0;
        X-Restart-Triggers = [ "${collieConfig}" ];
      };
      Service = {
        Type = "simple";
        WorkingDirectory = collieRoot;
        ExecStart = "${getExe collie.package} _exec-bridge";
        Restart = "on-failure";
        RestartSec = 5;
        # Paths only; settings come from config.toml and the mutable .env.
        Environment = [
          "HERDR_SOCKET_PATH=%h/.config/herdr/herdr.sock"
          "HERDR_PLUGIN_CONFIG_DIR=%h/.config/collie"
          "COLLIE_PLUGIN_ROOT=${collieRoot}"
          # git: the Changes view. tailscale: Host allowlist discovery.
          "PATH=${
            makeBinPath [
              cfg.package
              pkgs.git
              pkgs.tailscale
              pkgs.coreutils
            ]
          }"
        ];
        EnvironmentFile = "-%h/.config/collie/.env";
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # `tailscale serve --bg` state survives reboots; this oneshot keeps the
    # mapping declarative and removes it when Collie is disabled. tailscaled
    # is a system service the user manager can't order against, so retry.
    systemd.user.services.collie-tailscale-serve =
      mkIf (collie.enable && collie.tailscaleServe.enable)
        {
          Unit = {
            Description = "Publish Collie on the tailnet (tailscale serve)";
            After = [ "collie.service" ];
            PartOf = [ "collie.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "11min";
            ExecStart = toString (
              pkgs.writeShellScript "collie-tailscale-serve" ''
                for _ in {1..60}; do
                  if ${tailscale} serve --bg --https=${toString collie.tailscaleServe.port} \
                    http://127.0.0.1:${toString collie.port}; then
                    exit 0
                  fi
                  ${getExe' pkgs.coreutils "sleep"} 10
                done
                echo "tailscaled never accepted the serve config (is this user the tailscale operator?)" >&2
                exit 1
              ''
            );
            ExecStop = "-${tailscale} serve --https=${toString collie.tailscaleServe.port} off";
          };
          Install.WantedBy = [ "collie.service" ];
        };

    xdg.configFile."herdr/config.toml" = mkIf (cfg.settings != { }) {
      source = tomlFormat.generate "herdr-config.toml" cfg.settings;
    };

    # Keep the agent integration hooks in sync with the installed herdr
    # version on every activation. Install is idempotent and writes only to
    # per-agent dotfiles; a failure is non-fatal so it never aborts a switch.
    home.activation.herdrIntegrations = mkIf (cfg.integrations != [ ]) (
      hm.dag.entryAfter [ "writeBoundary" ] (
        concatMapStringsSep "\n" (agent: ''
          run ${cfg.package}/bin/herdr integration install ${agent} \
            || echo "herdr: 'integration install ${agent}' failed (non-fatal)" >&2
        '') cfg.integrations
      )
    );
  };
}
