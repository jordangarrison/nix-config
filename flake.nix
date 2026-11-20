{
  description = "Jordan Garrison's NixOS and Home Manager configurations for NixOS and MacOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-master.url = "github:nixos/nixpkgs/master";
    # Reuse the deployed Noctalia/Quickshell closure: its frozen fork fails
    # with Qt 6.12 (quickshell #1235). Remove this UI-only pin when the fork
    # includes 5d5d498 or Noctalia moves off the frozen fork.
    nixpkgs-noctalia.url = "github:nixos/nixpkgs/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aws-tools = {
      url = "github:jordangarrison/aws-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aws-use-sso = {
      url = "github:jordangarrison/aws-use-sso";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hubctl = {
      url = "github:jordangarrison/hubctl";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Linux dictation: keep the release tag explicit; update it and the lock together.
    hex = {
      url = "github:anomalyco/hex/v3.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # Herdr app layout by JinJieBeWater. Source only; the herdr-app module
    # copies its mods and layout into ~/.config/herdr-app.
    herdr-t3 = {
      url = "github:JinJieBeWater/herdr-t3";
      flake = false;
    };
    # Herdr app spaces list with folders, by jankeesvw. Source only; the
    # herdr-app module links its mod and layout into ~/.config/herdr-app.
    herdr-space-folders = {
      url = "github:jankeesvw/herdr-space-folders";
      flake = false;
    };
    # Herdr app GitHub issues panel, by jankeesvw. Source only; the
    # herdr-app module links its mod and layout into ~/.config/herdr-app.
    herdr-issues = {
      url = "github:jankeesvw/herdr-issues";
      flake = false;
    };
    # Herdr app vitals window, by mrolafsson. Source only; the herdr-app
    # module copies app/mods/vitals. The mod downloads its own binary.
    herdr-vitals = {
      url = "github:mrolafsson/herdr-vitals";
      flake = false;
    };
    # Herdr app Linear popup, by mrolafsson. Source only. The herdr-app
    # module copies app/mods/linear and builds the Go binary from this input.
    herdr-linear = {
      url = "github:mrolafsson/herdr-linear";
      flake = false;
    };
    # Herdr app Revive, by dmazlum. Source only. Resumes the agent a herdr-core
    # terminal lost to a reboot; the herdr-app module copies mods/revive and
    # wires its pi extension, zsh block and Claude Code hooks. Pinned to a
    # release tag because it runs in every shell start and agent session:
    # read the release notes, then change the tag to update.
    herdr-revive = {
      url = "github:dmazlum/herdr-revive/v0.5.1";
      flake = false;
    };
    niri.url = "github:sodiboo/niri-flake";
    noctalia = {
      # Keep the known v4 (QML/quickshell) snapshot. v5 is a ground-up C++
      # rewrite with an incompatible config schema; migrate settings.json
      # separately from the input/security refresh.
      url = "github:noctalia-dev/noctalia-shell/40dd5f54a0597b77ff78ac6a3a6d2ef42f04d544";
      inputs.nixpkgs.follows = "nixpkgs-noctalia";
    };
    sweet-nothings = {
      url = "github:jordangarrison/sweet-nothings";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    focus-fox = {
      url = "github:jordangarrison/focus-fox";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-nightly.url = "github:nix-community/flake-firefox-nightly";
    nix-zed-extensions = {
      url = "github:DuskSystems/nix-zed-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    greenlight = {
      url = "github:jordangarrison/greenlight";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    panko = {
      url = "github:jordangarrison/panko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    drawl = {
      url = "github:jordangarrison/drawl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    tic-tac-toe-4-in-a-row = {
      url = "github:jordangarrison/tic-tac-toe-4-in-a-row";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lakeline-cg = {
      url = "git+ssh://forgejo@forgejo.jordangarrison.dev/jordangarrison/cg.git";
    };
    grove = {
      url = "github:MichaelVessia/grove";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Private flocasts repo — fetched over SSH, so `nh flake update` needs
    # GitHub SSH access (the daily update-flake-lock action can't touch it).
    # No nixpkgs follows on purpose: consume the exact toolchain floai's CI
    # tests (its own nixpkgs pin, bun version).
    floai = {
      url = "git+ssh://git@github.com/flocasts/floai";
    };
    # Private repo, fetched over SSH like floai (same `nh flake update`
    # caveat). No nixpkgs follows for the same reason: run jagpi on the
    # nixpkgs (nodejs_24) its own lock was tested with. A new jagpi release
    # is `nix flake update jagpi` plus a switch.
    jagpi = {
      url = "git+ssh://git@github.com/jordangarrison/jagpi";
    };
    tuicr = {
      url = "github:agavra/tuicr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    onwatch = {
      url = "github:onllm-dev/onwatch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    try = {
      url = "github:tobi/try";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    warp-preview = {
      url = "github:jordangarrison/warp-preview-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    grok-bot = {
      url = "github:jordangarrison/grok-bot-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sre-claude-auto-runner = {
      url = "git+ssh://forgejo@forgejo.jordangarrison.dev/jordangarrison/sre-claude-auto-runner.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Fork branch that adds nixosModules.default. Repoint at
    # github:mago0/isp-snitch once that PR merges upstream.
    isp-snitch = {
      url = "github:jordangarrison/isp-snitch/feat-nix-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    maple = {
      # Upstream v0.3.6 currently packages the v0.3.5 binary bundle.
      url = "github:MapleTechLabs/maple/v0.3.6";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent skill sources (plain SKILL.md trees, consumed by
    # programs.agent-skills.external in users/jordangarrison/home.nix).
    # Skills for CLIs we package come from the package itself instead, so
    # skill and CLI versions stay in step.
    anthropic-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };
    archify = {
      url = "github:tt-a1i/archify";
      flake = false;
    };
    ash-kindle = {
      url = "github:jordangarrison/ash-kindle";
      flake = false;
    };
    boristane-agent-skills = {
      url = "github:boristane/agent-skills";
      flake = false;
    };
    caveman = {
      url = "github:JuliusBrussee/caveman";
      flake = false;
    };
    diagram-design = {
      url = "github:cathrynlavery/diagram-design";
      flake = false;
    };
    # Cursor's plugin repo. Only pstack/skills is used (poteto's pstack,
    # MIT); the plugin's agents/ and Cursor rules are not installed.
    cursor-plugins = {
      url = "github:cursor/plugins";
      flake = false;
    };
    lavish-axi = {
      url = "github:kunchenguid/lavish-axi";
      flake = false;
    };
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };
    obsidian-skills = {
      url = "github:kepano/obsidian-skills";
      flake = false;
    };
    readwise-skills = {
      url = "github:readwiseio/readwise-skills";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-stable,
      nixpkgs-master,
      nixos-hardware,
      deploy-rs,
      nix-darwin,
      home-manager,
      nvf,
      aws-tools,
      aws-use-sso,
      hubctl,
      llm-agents,
      niri,
      noctalia,
      sweet-nothings,
      focus-fox,
      firefox-nightly,
      nix-zed-extensions,
      greenlight,
      panko,
      drawl,
      tic-tac-toe-4-in-a-row,
      lakeline-cg,
      grove,
      floai,
      jagpi,
      tuicr,
      warp-preview,
      grok-bot,
      sre-claude-auto-runner,
      disko,
      isp-snitch,
      # Skill sources are only read through `inputs` (home.nix).
      ...
    }:
    {
      # Intentionally a small fleet, not every nixosConfiguration. Voyager
      # currently runs Omarchy; opportunity is a laptop. See docs/runbooks/deploy.md.
      deploy = {
        sshUser = "jordangarrison";
        user = "root";
        sudo = "sudo -n -u";
        interactiveSudo = false;
        sshOpts = [
          "-o" "BatchMode=yes"
          "-o" "StrictHostKeyChecking=yes"
          "-o" "ConnectTimeout=10"
          "-o" "ServerAliveInterval=15"
          "-o" "ServerAliveCountMax=3"
        ];
        remoteBuild = false;
        autoRollback = true;
        magicRollback = true;
        activationTimeout = 600;
        confirmTimeout = 60;
        nodes = builtins.mapAttrs (name: hostname: {
          inherit hostname;
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.${name};
        }) {
          # The guarded command runs on endeavour. Avoid its stale SSH alias.
          endeavour = "localhost";
          discovery = "discovery";
        };
      };

      packages.x86_64-linux.deploy-rs = deploy-rs.packages.x86_64-linux.default;
      packages.x86_64-linux.deploy-always-on =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          mkScript = pkgs.callPackage ./lib/mkScript.nix { };
        in mkScript {
          name = "deploy-always-on";
          script = ./packages/deploy-always-on/deploy-always-on.sh;
          deps = [ self.packages.x86_64-linux.deploy-rs ]
            ++ (with pkgs; [ bash coreutils jq nix openssh util-linux ]);
          description = "Build, test, and confirm deployment of the always-on NixOS fleet";
        };

      # Add deployChecks alongside (not instead of) the existing module checks.
      checks.x86_64-linux.deploy-schema =
        (deploy-rs.lib.x86_64-linux.deployChecks self.deploy).deploy-schema;
      checks.x86_64-linux.deploy-activate =
        (deploy-rs.lib.x86_64-linux.deployChecks self.deploy).deploy-activate;
      checks.x86_64-linux.deploy-wrapper =
        let pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in pkgs.runCommand "deploy-wrapper-tests" {
          nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.shellcheck pkgs.jq pkgs.util-linux ];
        } ''
          shellcheck ${./packages/deploy-always-on/deploy-always-on.sh}
          python3 ${./tests/deploy-wrapper.py} ${./packages/deploy-always-on/deploy-always-on.sh}
          touch "$out"
        '';
      checks.x86_64-linux.deploy-policy =
        let pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in pkgs.runCommand "deploy-policy-tests" {
          results = builtins.toJSON (import ./tests/deploy-policy.nix { flake = self; });
        } ''
          printf '%s\n' "$results" > "$out"
        '';

      checks.x86_64-linux.t3code-module =
        self.nixosConfigurations.endeavour.pkgs.runCommand "t3code-module-tests" {
          results = builtins.toJSON (import ./tests/t3code-module.nix { flake = self; });
        } ''
          printf '%s\n' "$results" > "$out"
        '';

      checks.x86_64-linux.hermes-module =
        self.nixosConfigurations.endeavour.pkgs.runCommand "hermes-module-tests" {
          results = builtins.toJSON (import ./tests/hermes-module.nix { flake = self; });
        } ''
          printf '%s\n' "$results" > "$out"
        '';

      checks.x86_64-linux.hermes-runtime = import ./tests/hermes-runtime.nix {
        inherit (self.nixosConfigurations.endeavour) pkgs config;
      };

      checks.x86_64-linux.maple-module =
        self.nixosConfigurations.endeavour.pkgs.runCommand "maple-module-tests" {
          results = builtins.toJSON (import ./tests/maple-module.nix { flake = self; });
        } ''
          printf '%s\n' "$results" > "$out"
        '';

      checks.x86_64-linux.otel-collector-module =
        self.nixosConfigurations.endeavour.pkgs.runCommand "otel-collector-module-tests" {
          results = builtins.toJSON (import ./tests/otel-collector-module.nix { flake = self; });
        } ''
          printf '%s\n' "$results" > "$out"
        '';

      checks.x86_64-linux.otel-collector-runtime = import ./tests/otel-collector-runtime.nix {
        inherit (self.nixosConfigurations.endeavour) pkgs;
      };

      checks.x86_64-linux.ovis-module =
        self.nixosConfigurations.endeavour.pkgs.runCommand "ovis-module-tests" {
          results = builtins.toJSON (import ./tests/ovis-module.nix { flake = self; });
        } ''
          printf '%s\n' "$results" > "$out"
        '';

      checks.x86_64-linux.ovis-pi-integration =
        let
          inherit (self.nixosConfigurations.endeavour) pkgs config;
          integration = config.home-manager.users.jordangarrison.programs.pi.extensions.files."herdr-web-ui.js".source;
        in
        pkgs.runCommand "ovis-pi-integration-tests" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
          cp ${integration} integration.mjs
          node ${./tests/ovis-pi-integration.mjs} "$PWD/integration.mjs"
          touch "$out"
        '';

      checks.x86_64-linux.pi-extensions =
        nixpkgs.legacyPackages.x86_64-linux.callPackage ./tests/pi-extensions { };

      nixosConfigurations = {
        "endeavour" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/zed-extensions-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/llm-agents-overlay.nix
            ./modules/okta-cli-client-overlay.nix
            ./modules/readwise-cli-overlay.nix
            ./modules/varlock-overlay.nix
            ./modules/pup-overlay.nix
            ./modules/namespace-cli-overlay.nix
            ./modules/sidecar-overlay.nix
            ./modules/codiff-overlay.nix
            ./modules/plannotator-overlay.nix
            ./modules/orca-overlay.nix
            ./modules/stack-cli-overlay.nix
            ./modules/brave-overlay.nix
            ./modules/tea-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            ./modules/nixos/niri-desktop.nix
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/audio/speech-dispatcher.nix
            ./modules/nixos/development.nix
            ./modules/nixos/searx.nix
            ./modules/super-productivity/server.nix
            ./modules/super-productivity/app.nix
            ./modules/nixos/postgres.nix
            ./modules/nixos/greenlight.nix
            ./modules/nixos/panko.nix
            ./modules/nixos/agentsview.nix
            ./modules/nixos/onwatch.nix
            ./modules/nixos/collie.nix
            ./modules/nixos/executor.nix
            ./modules/nixos/maple.nix
            ./modules/nixos/otel-collector.nix
            ./modules/nixos/nginx-tracing.nix
            ./modules/nixos/isp-snitch.nix
            ./modules/nixos/norish.nix
            ./modules/nixos/hermes.nix
            ./modules/nixos/drawl.nix
            ./modules/nixos/tic-tac-toe-4-in-a-row.nix
            ./modules/nixos/cloudflared.nix
            ./modules/nixos/nginx.nix
            ./modules/nixos/jellyfin.nix
            ./modules/nixos/home-assistant.nix
            ./modules/nixos/forgejo.nix
            ./modules/nixos/forgejo-runner.nix
            ./modules/nixos/virtualization.nix
            ./modules/nixos/freerdp.nix
            ./modules/nixos/blocky.nix
            ./modules/nixos/lakeline-cg.nix
            ./modules/nixos/sre-claude-auto-runner.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/endeavour/configuration.nix
            ./modules/nixos/deploy-target.nix
            nixos-hardware.nixosModules.msi-b550-a-pro
            nixos-hardware.nixosModules.common-gpu-amd
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            greenlight.nixosModules.default
            panko.nixosModules.default
            drawl.nixosModules.default
            tic-tac-toe-4-in-a-row.nixosModules.default
            lakeline-cg.nixosModules.default
            isp-snitch.nixosModules.default
            (
              {
              # Configure users for endeavour
              users.jordangarrison = {
                enable = true;
                username = "jordangarrison";
                homeDirectory = "/home/jordangarrison";
                apps = {
                  slack.enable = true;
                  spotify.enable = true;
                  discord.enable = true;
                  signal.enable = true;
                  obs.enable = true;
                  obsidian.enable = true;
                  todoist.enable = true;
                  nextcloud.enable = true;
                  deskflow.enable = true;
                  codex.enable = true;
                  t3code.enable = true;
                  codiff.enable = true;
                  plannotator.enable = true;
                  google-cloud-sdk.enable = true;
                  azure-cli.enable = true;
                  okta.enable = true;
                  pup.enable = true;
                  namespace.enable = true;
                  handy.enable = true;
                  # Disabled Nov 18: Hex holds the mic and blocks Handy.
                  hex.enable = false;
                  herdr.enable = true;
                  herdr-app.enable = true;
                  ovis.enable = true;
                  work.enable = true;
                  aikido.enable = true;
                  floai.enable = true;
                  grok-bot.enable = true;
                };
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };

              # Enable virtualization with virt-manager
              virtualization.virt-manager = {
                enable = true;
                users = [ "jordangarrison" ];
              };

              # Enable FreeRDP
              services.freerdp.enable = true;

              # Enable DNS-level ad blocking
              services.dns-blocking.enable = true;

              # Super Productivity: sync server + web app, and the desktop app.
              services.super-productivity.enable = false; # disabled 2026-11-20 by Jordan
              programs.super-productivity.enable = false; # disabled 2026-11-20 by Jordan

              # Import home modules for jordangarrison on endeavour
              home-manager.users.jordangarrison.imports = [
                ./modules/home/niri
                ./modules/home/orca
                ./modules/home/tea
                ./modules/home/yazi
                ./hosts/endeavour/jagpi.nix
              ];

              home-manager.users.jordangarrison.programs.orca.enable = false;

              # Configure tea CLI for Forgejo access
              home-manager.users.jordangarrison.programs.tea = {
                enable = true;
                logins.endeavour = {
                  url = "https://forgejo.jordangarrison.dev";
                  user = "jordangarrison";
                  default = true;
                  tokenFile = "/home/jordangarrison/.config/tea/endeavour-token";
                  sshHost = "forgejo.jordangarrison.dev";
                  sshKey = "~/.ssh/id_ed25519";
                  sshAgent = true;
                };
              };
            }
            )
          ];

        };
        "opportunity" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/zed-extensions-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/llm-agents-overlay.nix
            ./modules/okta-cli-client-overlay.nix
            ./modules/readwise-cli-overlay.nix
            ./modules/varlock-overlay.nix
            ./modules/pup-overlay.nix
            ./modules/namespace-cli-overlay.nix
            ./modules/sidecar-overlay.nix
            ./modules/codiff-overlay.nix
            ./modules/plannotator-overlay.nix
            ./modules/orca-overlay.nix
            ./modules/stack-cli-overlay.nix
            ./modules/brave-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            # ./modules/nixos/hyprland-desktop.nix  # Disabled in favor of Niri
            ./modules/nixos/niri-desktop.nix
            { gbg-config.machine.type = "laptop"; }
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/audio/speech-dispatcher.nix
            ./modules/nixos/development.nix
            ./modules/nixos/virtualization.nix
            ./modules/nixos/tablet-mode.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/opportunity/configuration.nix
            ./modules/super-productivity/app.nix
            nixos-hardware.nixosModules.framework-12-13th-gen-intel
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              # Configure users for opportunity
              users.jordangarrison = {
                enable = true;
                username = "jordangarrison";
                homeDirectory = "/home/jordangarrison";
                # super/alt swap is handled per-device by interception-tools
                # (see hosts/opportunity/configuration.nix). Compositor-level
                # XKB swap is off so QMK/external boards aren't double-swapped.
                swapSuperAlt = false;
                apps = {
                  slack.enable = true;
                  spotify.enable = true;
                  discord.enable = true;
                  signal.enable = true;
                  obs.enable = true;
                  obsidian.enable = true;
                  todoist.enable = true;
                  nextcloud.enable = true;
                  codex.enable = true;
                  t3code.enable = true;
                  codiff.enable = true;
                  plannotator.enable = true;
                  google-cloud-sdk.enable = true;
                  okta.enable = true;
                  pup.enable = true;
                  handy.enable = true;
                  # Disabled Nov 18: Hex holds the mic and blocks Handy.
                  hex.enable = false;
                  herdr.enable = true;
                  herdr-app.enable = true;
                  work.enable = true;
                  grok-bot.enable = true;
                };
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };

              # Import niri and tablet-mode home modules for jordangarrison on opportunity
              home-manager.users.jordangarrison.imports = [
                ./modules/home/niri
                ./modules/home/orca
                ./modules/home/tablet-mode
                ./modules/home/yazi
              ];

              home-manager.users.jordangarrison.programs.orca.enable = false;

              # Enable virtualization with virt-manager
              virtualization.virt-manager = {
                enable = true;
                users = [ "jordangarrison" ];
              };

              # Enable tablet mode for Framework 12 touchscreen
              tablet-mode.enable = true;

              programs.super-productivity.enable = false; # disabled 2026-11-20 by Jordan

            }
          ];

        };
        "voyager" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/llm-agents-overlay.nix
            ./modules/okta-cli-client-overlay.nix
            ./modules/readwise-cli-overlay.nix
            ./modules/varlock-overlay.nix
            ./modules/pup-overlay.nix
            ./modules/namespace-cli-overlay.nix
            ./modules/sidecar-overlay.nix
            ./modules/codiff-overlay.nix
            ./modules/plannotator-overlay.nix
            ./modules/stack-cli-overlay.nix
            ./modules/brave-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            # "desktop" despite being a MacBook: treated as an always-on server
            # because S3 permanently kills the SD reader backing /data (no
            # software recovery, only a cold power-off). This disables suspend
            # and GDM auto-suspend. See hosts/voyager/configuration.nix.
            { gbg-config.machine.type = "desktop"; }
            # ./modules/nixos/hyprland-desktop.nix  # Disabled - voyager uses GNOME only
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/audio/speech-dispatcher.nix
            ./modules/nixos/development.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/voyager/configuration.nix
            ./modules/super-productivity/app.nix
            inputs.disko.nixosModules.disko
            (import ./hosts/voyager/disko.nix { })
            nixos-hardware.nixosModules.apple-macbook-pro-12-1
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              programs.super-productivity.enable = false; # disabled 2026-11-20 by Jordan

              # Configure users for voyager
              users.jordangarrison = {
                enable = true;
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };
            }
          ];

        };
        # Installer ISO for voyager: minimal live CD + the full voyager
        # closure + a guided install script. Built via packages.voyager-iso.
        "voyager-installer" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            voyagerToplevel = self.nixosConfigurations.voyager.config.system.build.toplevel;
            voyagerDiskoScript = self.nixosConfigurations.voyager.config.system.build.diskoScript;
          };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./hosts/voyager/installer.nix
          ];
        };
        "discovery" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/llm-agents-overlay.nix
            ./modules/okta-cli-client-overlay.nix
            ./modules/readwise-cli-overlay.nix
            ./modules/varlock-overlay.nix
            ./modules/pup-overlay.nix
            ./modules/namespace-cli-overlay.nix
            ./modules/sidecar-overlay.nix
            ./modules/codiff-overlay.nix
            ./modules/plannotator-overlay.nix
            ./modules/stack-cli-overlay.nix
            ./modules/brave-overlay.nix
            ./modules/nixos/common.nix
            ./modules/nixos/brother-printer.nix
            ./modules/nixos/lan.nix
            ./modules/nixos/gnome-desktop.nix
            ./modules/nixos/fonts.nix
            ./modules/nixos/audio/pipewire.nix
            ./modules/nixos/audio/speech-dispatcher.nix
            ./users/jordangarrison/nixos.nix
            ./users/mikayla/nixos.nix
            ./users/jane/nixos.nix
            ./users/isla/nixos.nix
            ./hosts/discovery/configuration.nix
            ./modules/nixos/deploy-target.nix
            ./modules/super-productivity/app.nix
            nixos-hardware.nixosModules.common-cpu-amd
            nixos-hardware.nixosModules.common-pc-ssd
            home-manager.nixosModules.home-manager
            ./modules/home/defaults.nix
            {
              programs.super-productivity.enable = false; # disabled 2026-11-20 by Jordan

              # Configure users for discovery (GNOME desktop with PipeWire).
              users.jordangarrison = {
                enable = true;
                username = "jordangarrison";
                homeDirectory = "/home/jordangarrison";
                # Disabled Nov 18: Hex holds the mic and blocks Handy.
                apps.hex.enable = false;
              };

              users.mikayla = {
                enable = true;
                homeDirectory = "/home/mikayla";
              };

              users.jane = {
                enable = true;
                homeDirectory = "/home/jane";
              };

              users.isla = {
                enable = true;
                homeDirectory = "/home/isla";
              };
            }
          ];
        };
      };

      darwinConfigurations = {
        "H952L3DPHH" = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/llm-agents-overlay.nix
            ./modules/okta-cli-client-overlay.nix
            ./modules/readwise-cli-overlay.nix
            ./modules/varlock-overlay.nix
            ./modules/pup-overlay.nix
            ./modules/namespace-cli-overlay.nix
            ./modules/sidecar-overlay.nix
            ./modules/codiff-overlay.nix
            ./modules/plannotator-overlay.nix
            ./modules/stack-cli-overlay.nix
            ./modules/nixos/emacs.nix
            ./modules/nixos/fonts.nix
            ./hosts/flomac/configuration.nix
            ./modules/super-productivity/app.nix
            home-manager.darwinModules.home-manager
            ./modules/home/defaults.nix
            {
              nix.enable = false;
              programs.super-productivity.enable = false; # disabled 2026-11-20 by Jordan
              nixpkgs.config.allowUnfree = true;
              home-manager = {
                users."jordan.garrison" = import ./users/jordangarrison/home-darwin.nix;
                extraSpecialArgs = {
                  inherit inputs;
                  username = "jordan.garrison";
                  homeDirectory = "/Users/jordan.garrison";
                  userApps = {
                    grok-bot.enable = true;
                    # Same llm-agents release as the other hosts. Do not add the
                    # Homebrew cask; its updater would drift ahead of the server.
                    t3code.enable = true;
                    azure-cli.enable = true;
                    plannotator.enable = true;
                    pup.enable = true;
                    namespace.enable = true;
                    herdr.enable = true;
                    herdr-app.enable = true;
                    work.enable = true;
                    aikido.enable = true;
                    floai.enable = true;
                    # Off for now: back on Stage Manager + Rectangle. Set to
                    # true to try OmniWM; see modules/home/omniwm/README.md.
                    omniwm.enable = false;
                  };
                };
              };
              users.users."jordan.garrison" = {
                home = "/Users/jordan.garrison";
              };
            }
          ];
        };
      };

      # Ubuntu/WSL configuration
      homeConfigurations = {
        "jordangarrison@normandy" = home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            localSystem.system = "x86_64-linux";
            config.allowUnfree = true;
          };
          modules = [
            ./modules/stable-overlay.nix
            ./modules/master-overlay.nix
            ./modules/ralph-overlay.nix
            ./modules/scripts-overlay.nix
            ./modules/llm-agents-overlay.nix
            ./modules/okta-cli-client-overlay.nix
            ./modules/readwise-cli-overlay.nix
            ./modules/varlock-overlay.nix
            ./modules/pup-overlay.nix
            ./modules/namespace-cli-overlay.nix
            ./modules/sidecar-overlay.nix
            ./modules/codiff-overlay.nix
            ./modules/plannotator-overlay.nix
            ./modules/stack-cli-overlay.nix
            ./modules/brave-overlay.nix
            ./users/jordangarrison/home.nix
          ];
          extraSpecialArgs = {
            inherit inputs;
            username = "jordangarrison";
            homeDirectory = "/home/jordangarrison";
            # Module-arg defaults (`userApps ? { }`) are ignored by the module
            # system — the arg must be provided, as nixos.nix and the darwin
            # config both do. No optional apps on the WSL box.
            userApps = { };
          };
        };
      };

      packages.x86_64-linux.voyager-iso =
        self.nixosConfigurations.voyager-installer.config.system.build.isoImage;
    };
}
