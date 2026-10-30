{
  config,
  pkgs,
  lib,
  username,
  homeDirectory,
  inputs,
  userApps ? { },
  ...
}:

let
  borkedNsScriptPath = pkgs.writeTextFile {
    name = "borked-ns";
    text = builtins.readFile ./tools/scripts/borked-ns.sh;
  };
  binauralBeatsScriptPath = pkgs.writeTextFile {
    name = "binarual-beats";
    text = builtins.readFile ./tools/scripts/binaural-beats.sh;
  };
  # Use pgtk variant on Linux for native Wayland support
  emacsPackage = if pkgs.stdenv.hostPlatform.isLinux then pkgs.emacs-pgtk else pkgs.emacs;
  # Live-checkout path for hand-authored agent content (see ./agents)
  agentsLive = "${config.home.homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/agents";
  # Shape one programs.mcp server for a client: `remote` for url servers,
  # `local` for stdio (command) servers.
  mcpEntry = remote: local: s: if s.command != null then local s else remote s;
  mcpStdio = s: { inherit (s) command args; };
in
{
  imports = [
    inputs.try.homeModules.default
    ./tools/nvim/nvf.nix
    ../../modules/home/acp-adapters
    ../../modules/home/languages
    ../../modules/home/pi
    ../../modules/home/herdr
    ../../modules/home/tuicr
    ../../modules/home/bb
    ../../modules/home/bb-desktop
    ../../modules/home/agent-skills
    ../../modules/home/agent-workspaces
    ../../modules/home/claude-code
    ../../modules/home/codex
    ../../modules/home/cursor-agent
  ];

  programs.bb-desktop = {
    enable = userApps.bb-desktop.enable or false;
    defaultServerUrl = "https://bb.jordangarrison.dev";
  };

  programs.agent-skills = {
    enable = true;
    skillsDir = ./skills;
    liveDir = "${config.home.homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/skills";
    # Upstream skills. Skills for a CLI come from that CLI's package, so
    # they are gated with it and version-locked to it; the rest come from
    # `flake = false` inputs. See docs/plans/2026-09-23-declarative-agent-skills.md.
    external =
      let
        fromDir = dir: names: lib.genAttrs names (name: "${dir}/${name}");
        # pup embeds its skills in the binary. The platform argument is
        # required but only picks a target directory, which --dir overrides;
        # the SKILL.md files are identical for every platform.
        pupSkills = pkgs.runCommand "pup-skills-${pkgs.pup.version}" {
          nativeBuildInputs = [ pkgs.pup ];
        } ''
          export HOME=$TMPDIR
          pup skills install codex --type=skill --dir $out --no-agent
        '';
      in
      lib.mkMerge [
        (fromDir "${pkgs.gws.src}/skills" [
          "gws-shared"
          "gws-gmail"
          "gws-gmail-read"
          "gws-gmail-reply"
          "gws-gmail-reply-all"
          "gws-gmail-send"
          "gws-gmail-triage"
          "gws-drive"
          "gws-drive-upload"
          "gws-docs"
          "gws-docs-write"
          "gws-sheets"
          "gws-sheets-read"
          "gws-calendar"
          "gws-calendar-agenda"
          "gws-people"
        ])
        (fromDir "${pkgs.master.gh-stack.src}/skills" [ "gh-stack" ])
        (fromDir "${inputs.aws-use-sso}/skills" [ "aws-use-sso" ])
        (fromDir "${inputs.anthropic-skills}/skills" [ "frontend-design" ])
        (fromDir "${inputs.archify}" [ "archify" ])
        (fromDir "${inputs.ash-kindle}/skills" [ "ash-kindle" ])
        (fromDir "${inputs.boristane-agent-skills}/skills" [ "logging-best-practices" ])
        (fromDir "${inputs.caveman}/skills" [ "caveman" ])
        (fromDir "${inputs.diagram-design}/skills" [ "diagram-design" ])
        (fromDir "${inputs.lavish-axi}/skills" [ "lavish" ])
        (fromDir "${inputs.mattpocock-skills}/skills/engineering" [
          "code-review"
          "codebase-design"
          "diagnosing-bugs"
          "domain-modeling"
          "grill-with-docs"
          "implement-spec"
          "improve-codebase-architecture"
          "pr"
          "retro"
          "setup-matt-pocock-skills"
          "tdd"
          "to-spec"
          "to-tickets"
          "wayfinder"
          "wizard"
        ])
        (fromDir "${inputs.mattpocock-skills}/skills/productivity" [
          "grill-me"
          "grilling"
          "handoff"
          "to-questionnaire"
          "wait-what"
          "writing-for-agents"
        ])
        (fromDir "${inputs.obsidian-skills}/skills" [
          "obsidian-bases"
          "obsidian-cli"
          "obsidian-markdown"
        ])
        (fromDir "${inputs.readwise-skills}/skills" [
          "book-review"
          "build-persona"
          "feed-catchup"
          "highlight-graph"
          "now-reading-page"
          "quiz"
          "reader-recap"
          "readwise-cli"
          "surprise-me"
          "triage"
        ])
        (lib.mkIf (userApps.herdr.enable or false) (
          fromDir "${config.programs.herdr.package.src}/skills" [ "herdr" ]
        ))
        (lib.mkIf (userApps.pup.enable or false) (
          fromDir pupSkills [
            "dd-apm"
            "dd-code-generation"
            "dd-debugger"
            "dd-docs"
            "dd-file-issue"
            "dd-logs"
            "dd-monitors"
            "dd-pup"
            "dd-symdb"
            "dd-triage-flaky-test"
            "dd-unblock-pr"
          ]
        ))
        (lib.mkIf (userApps.floai.enable or false) (
          fromDir "${inputs.floai}/catalog/skills" [
            "flo-brand-naming"
            "git-update-pr-description"
            "setup-pitch-ci"
            "using-flo-cli"
            "using-flo-pitch"
          ]
        ))
      ];
  };

  # Agent CLI configs (claude/codex) + workspace routers. Hand-authored
  # content lives in ./agents and is symlinked out-of-store from the live
  # checkout; settings/config files that the tools mutate at runtime are
  # merged on activation, never made read-only. See docs/plans/
  # nixify-agent-configs.md.
  programs.claude-code = {
    enable = true;
    instructionsFile = "${agentsLive}/AGENTS.md";
    files = {
      "workflows/deep-research-staged.js" = "${agentsLive}/claude/workflows/deep-research-staged.js";
      "statusline.sh" = "${agentsLive}/claude/statusline.sh";
    };
    settings = {
      model = "claude-opus-5-5";
      theme = "auto";
      tui = "fullscreen";
      editorMode = "normal";
      alwaysThinkingEnabled = true;
      includeCoAuthoredBy = false;
      attribution.sessionUrl = false;
      agentPushNotifEnabled = true;
      inputNeededNotifEnabled = true;
      voiceEnabled = true;
      remoteControlAtStartup = true;
      skillListingBudgetFraction = 0.02;
      skipAutoPermissionPrompt = true;
      skipDangerousModePermissionPrompt = true;
      permissions.defaultMode = "bypassPermissions";
      statusLine = {
        type = "command";
        command = ''bash "$HOME/.claude/statusline.sh"'';
      };
      # MCP comes only from programs.mcp (the Executor gateways). The Slack
      # plugin and claude.ai account connectors would each add direct
      # servers for integrations Executor already covers.
      enabledPlugins."slack@claude-plugins-official" = false;
      disableClaudeAiConnectors = true;
    };
  };

  # Cursor Agent CLI. cli-config.json is merge-on-activation (auth, model,
  # and the permissions allowlist stay mutable). unrestricted + disabled
  # sandbox match claude's bypassPermissions and codex's danger-full-access.
  programs.cursor-agent = {
    enable = true;
    settings = {
      approvalMode = "unrestricted";
      sandbox.mode = "disabled";
    };
  };

  programs.codex = {
    enable = true;
    instructionsFile = "${agentsLive}/AGENTS.md";
    rules."default.rules" = "${agentsLive}/codex/rules/default.rules";
    config = {
      approval_policy = "never";
      sandbox_mode = "danger-full-access";
      model = "gpt-6-sol";
      model_reasoning_effort = "high";
      plan_mode_reasoning_effort = "xhigh";
      personality = "pragmatic";
      approvals_reviewer = "user";
      # Same list as programs.mcp. A deep merge, so servers codex or the
      # ChatGPT app add themselves (node_repl) stay.
      mcp_servers = lib.mkIf config.programs.mcp.enable (
        lib.mapAttrs (_: mcpEntry (s: { inherit (s) url; }) mcpStdio) config.programs.mcp.servers
      );
      tui = {
        status_line = [
          "model-with-reasoning"
          "current-dir"
          "git-branch"
          "context-used"
        ];
        theme = "1337";
        pet = "seedy";
      };
    };
  };

  programs.agent-workspaces = {
    enable = true;
    routerFile = "${agentsLive}/ROUTER.md";
    workspaces = {
      jordangarrison = {
        directory = "dev/jordangarrison";
        additionsFile = "${agentsLive}/workspaces/jordangarrison-additions.md";
      };
      flocasts = {
        directory = "dev/flocasts";
        # additions stay a local untracked file (work content, public repo)
      };
      kartingcoach = {
        directory = "dev/kartingcoach";
        additionsFile = "${agentsLive}/workspaces/kartingcoach-additions.md";
      };
    };
  };

  languages = {
    clojure.enable = true;
    elixir.enable = true;
    erlang.enable = true;
    gleam.enable = true;
  };

  # Nix settings (required for standalone Home Manager on non-NixOS systems)
  # Use mkDefault so NixOS Home Manager module can override with system's nix package
  nix.package = lib.mkDefault pkgs.nix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = username;
  home.homeDirectory = homeDirectory;

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You can update Home Manager without changing this value. See
  # the Home Manager release notes for a list of state version
  # changes in each release.
  home.stateVersion = "21.11";

  # PATH management
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.emacs.d/bin"
    "$HOME/.cargo/bin"
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ "/opt/homebrew/bin" ];

  # Environment variables
  home.sessionVariables = {
    DEV_PATH = "$HOME/dev";
    EDITOR = "nvim";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.pi = {
    enable = true;
    package = pkgs.llm-agents.pi;
    instructionsFile = "${agentsLive}/AGENTS.md";
    cacheRetention = "long";
    settings = {
      defaultProvider = "openai-codex";
      defaultModel = "gpt-6.1-sol";
      # Keep model cycling scoped to these exact provider/model IDs. Activation
      # replaces any runtime scope saved by /scoped-models.
      enabledModels = [
        "openai-codex/gpt-6.1-sol"
        "openai-codex/gpt-6-luna"
        "openai-codex/gpt-6-astra"
        "claude-bridge/claude-opus-5-5"
        "claude-bridge/claude-fable-5-1"
      ];
      # Third-party extensions at their latest release, installed unmodified
      # by pi itself into ~/.pi/agent/npm on first start. Move them forward
      # with `pi update --extensions`. Never patch their source: code we own
      # lives in modules/home/pi/extensions/.
      packages = [
        # Pinned to an upstream main commit that includes claude-opus-5-5 at
        # 1M (elidickinson/pi-claude-bridge#116, fixed after 0.8.0). When
        # `npm view pi-claude-bridge version` is newer than 0.8.0, replace
        # this with "npm:pi-claude-bridge" and run `pi update --extensions`.
        "git:github.com/elidickinson/pi-claude-bridge@07507489c0c54f7f978ab752eb9beb5cc0960f24"
        "npm:pi-subagents"
        "npm:pi-web-access"
        "npm:pi-foldable-tools"
        "git:github.com/joelhooks/pi-until"
      ];
      # Install with the Nix npm, so package installs do not depend on PATH.
      npmCommand = [ "${pkgs.nodejs}/bin/npm" ];
      # Thinking at xhigh produces pages of reasoning that push the actual
      # answer off screen. This collapses every thinking block to a single
      # italic "Thinking..." line; the reasoning still happens and is still
      # written to the session file, it just is not rendered.
      #
      # Ctrl+T (app.thinking.toggle) flips this live and writes the new value
      # back to settings.json, but the declarative merge here reasserts `true`
      # on the next activation — so a rebuild re-collapses the blocks.
      hideThinkingBlock = true;
    };

    # Local models served by ollama on flomac (the work MacBook), reached over
    # the tailnet rather than the LAN so this works from anywhere. flomac's
    # `tailscale serve` config and OLLAMA_CONTEXT_LENGTH live in
    # hosts/flomac/configuration.nix; contextWindow below must stay <= that
    # value or ollama silently truncates the prompt.
    #
    # These remain available through /model, but are excluded from the
    # declarative model-cycling scope above.
    models.providers.flomac = {
      baseUrl = "https://h952l3dphh.owl-yo.ts.net:11434/v1";
      api = "openai-completions";
      # Ollama ignores the key, but pi treats a provider with no auth at all
      # as unavailable and hides its models.
      apiKey = "ollama";
      compat = {
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
      };
      models = [
        {
          # Picked over dense Qwen3.8-27B and GLM-4.7-Flash by measurement on
          # this hardware, not by benchmark score. Only ~3B of its 35B params
          # are active per token, and generation here is memory-bandwidth
          # bound, so it runs ~8x faster than a dense 27B for comparable
          # answers: 49s on a representative pi subagent task versus 523s.
          #
          # The `-coding` tune is load-bearing, not cosmetic. The base
          # Qwen3.6-35B-A3B inverted a subtle claim about this very file that
          # the coding variant got right on every run. There is no MLX build
          # of the coding variant, which is why this stays on ollama rather
          # than moving to oMLX.
          id = "qwen3.6:35b-a3b-coding";
          name = "Qwen3.6 35B-A3B Coding (flomac)";
          reasoning = true;
          input = [ "text" ];
          contextWindow = 65536;
          maxTokens = 16384;
          cost = {
            input = 0;
            output = 0;
            cacheRead = 0;
            cacheWrite = 0;
          };
        }
      ];
    };

    # pi-subagents agents. PR review agents live beside the skill that runs
    # them; @HOME@ stands in for paths pi installs at run time (skills
    # fan-out, npm extensions). Generic agents live in agents/pi/.
    agents.files =
      let
        withHome =
          path:
          builtins.replaceStrings [ "@HOME@" ] [ config.home.homeDirectory ] (builtins.readFile path);
      in
      {
        "pr-review-specialist.md".text = withHome ./skills/multi-agent-pr-review/pi-agents/specialist.md;
        "pr-review-consolidator.md".text = withHome ./skills/multi-agent-pr-review/pi-agents/consolidator.md;
        "pr-review-slack-watcher.md".text = withHome ./skills/slack-pr-review/pi-agents/slack-watcher.md;
        # Not `researcher`: that name is a pi-subagents builtin (web research).
        "mcp-researcher.md".source = ./agents/pi/mcp-researcher.md;
      };
  };

  programs.acp-adapters = {
    enable = true;
  };

  # The one MCP server list for every agent. Integrations live behind two
  # Executor gateways instead of per-agent servers: FloSports' for work
  # connections, and the self-hosted one on endeavour (modules/nixos/executor.nix,
  # tailnet-only) for personal ones. Add new integrations in Executor, not
  # here. Both are OAuth with dynamic client registration; tokens land in
  # each client's keyring, not this file.
  #
  # The one exception is Aikido: it ships only a local stdio server that
  # scans code on this machine, and executor-flo cannot run stdio servers.
  # Its token is read at startup from ~/.config/aikido/api-key (see
  # packages/aikido-mcp), gated by userApps.aikido (endeavour, flomac).
  #
  # On every host, so agents never fall back to direct servers. The work
  # gateway only goes to hosts allowed to reach work (userApps.work: endeavour,
  # opportunity, flomac). Fanned out to each agent's own format below: pi,
  # Claude Code, Codex, Cursor and OpenCode.
  programs.mcp = {
    enable = true;
    servers.executor.url = "https://executor.jordangarrison.dev/mcp";
    servers.executor-flo = lib.mkIf (userApps.work.enable or false) {
      url = "https://executor.flostag-us-west-2.flokubernetes.com/mcp";
    };
    servers.aikido = lib.mkIf (userApps.aikido.enable or false) {
      command = lib.getExe pkgs.aikido-mcp;
    };
  };

  # Native Pi reads only ~/.pi/agent/mcp.json, not the shared config path.
  # Translate the OAuth field that differs without duplicating the server
  # inventory.
  home.file.".pi/agent/mcp.json" = lib.mkIf config.programs.mcp.enable {
    text = builtins.toJSON {
      mcpServers = lib.mapAttrs (_: mcpEntry (server:
        { inherit (server) url; }
        // lib.optionalAttrs (server.headers != { }) { inherit (server) headers; }
        // lib.optionalAttrs (server ? oauth) {
          oauth = (removeAttrs server.oauth [ "redirectUri" ])
            // lib.optionalAttrs (server.oauth ? redirectUri) {
              callbackUrl = server.oauth.redirectUri;
            };
        }
      ) mcpStdio) config.programs.mcp.servers;
    };
  };

  # Claude Code, Cursor and OpenCode keep their MCP lists inside files they
  # also write at runtime (session state, settings), so they can't be
  # store symlinks. Replace just the user-level server map on activation,
  # which drops anything not declared above. Claude Code's per-project
  # servers (`claude mcp add -s local`) are left alone for local dev
  # servers such as tidewave. A missing file is created holding only the
  # server map; the agent fills in the rest on first run.
  home.activation.mcpClientSync = lib.mkIf config.programs.mcp.enable (
    let
      servers = config.programs.mcp.servers;
      claude = pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON (
        lib.mapAttrs (_: mcpEntry
          (s: { type = "http"; inherit (s) url; })
          (s: { type = "stdio"; } // mcpStdio s)) servers));
      cursor = pkgs.writeText "cursor-mcp-servers.json" (builtins.toJSON (
        lib.mapAttrs (_: mcpEntry (s: { inherit (s) url; }) mcpStdio) servers));
      opencode = pkgs.writeText "opencode-mcp-servers.json" (builtins.toJSON (
        lib.mapAttrs (_: mcpEntry
          (s: { type = "remote"; inherit (s) url; enabled = true; })
          (s: { type = "local"; command = [ s.command ] ++ s.args; enabled = true; })) servers));
    in
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mcpSet() {
        local file="$1" key="$2" servers="$3"
        if [[ -v DRY_RUN ]]; then
          echo "Would set .$key in $file"
        elif [[ ! -e "$file" ]]; then
          mkdir -p "$(dirname "$file")"
          (
            umask 077
            ${pkgs.jq}/bin/jq -n --arg k "$key" --slurpfile s "$servers" '{($k): $s[0]}' > "$file"
          )
        elif ${pkgs.jq}/bin/jq empty "$file" 2>/dev/null; then
          (
            umask 077
            ${pkgs.jq}/bin/jq --arg k "$key" --slurpfile s "$servers" '.[$k] = $s[0]' "$file" \
              > "$file.hm-mcp"
          ) && mv "$file.hm-mcp" "$file"
        else
          warnEcho "$file is not valid JSON; skipping MCP server sync"
        fi
      }
      mcpSet "$HOME/.claude.json" mcpServers ${claude}
      mcpSet "$HOME/.cursor/mcp.json" mcpServers ${cursor}
      mcpSet "$HOME/.config/opencode/opencode.json" mcp ${opencode}
    ''
  );

  programs.herdr = {
    enable = userApps.herdr.enable or false;
    integrations = [
      "claude"
      "codex"
      "pi"
      "opencode"
    ];
    settings = {
      onboarding = false;
      theme.name = "rose-pine";
      # Agent panel as an attention queue (agents needing input first)
      # instead of grouped by workspace.
      ui.agent_panel_sort = "priority";
      ui.sound.enabled = false; # silence the agent state-change chime
      experimental.pane_history = true;
      session.resume_agents_on_restore = true;
      # Direct (no-prefix) grove-style navigation. Caveat: these are grabbed
      # globally, so terminal apps inside panes never see these Meta chords
      # (e.g. terminal Emacs M-h/M-j/M-k/M-l).
      keys = {
        focus_pane_left = "alt+h";
        focus_pane_down = "alt+j";
        focus_pane_up = "alt+k";
        focus_pane_right = "alt+l";
        previous_workspace = "alt+shift+k"; # up the sidebar list
        next_workspace = "alt+shift+j"; # down the sidebar list
        previous_tab = "alt+{";
        next_tab = "alt+}";
      };
    };
  };

  home.packages =
    with pkgs;
    [
      # nix utilities
      devenv
      nh
      devbox

      # LLM Agents (available via overlay as pkgs.llm-agents.*)
      llm-agents.claude-code
      llm-agents.cursor-agent
      llm-agents.grok # Grok Build, xAI's coding agent (`grok`)
      sox # Audio playback/recording, used by Claude Code
      otel-tui # Terminal OpenTelemetry viewer
      stack-cli # Squash-safe stacked PR/MR repair CLI (kitlangton/stack), installs `stack`

      # Ralph - iterative AI loop utility
      ralph

      # Script packages (wrapped with dependencies)
      myip # Public IP with geolocation
      gi # gitignore template fetcher
      tmux-cht # Cheat sheet lookup in tmux
      ksn # kubectl namespace switcher
      claude-switch # Claude Code credential profile switcher

      td
      readwise-cli # Readwise & Reader CLI
      varlock # AI-safe .env files: schemas for agents, secrets for humans

      # Apps
      arandr
      cliamp # Winamp-style terminal music player
      wezterm
      # doom-emacs

      # Tree-sitter grammars for Emacs
      emacsPackages.treesit-grammars.with-all-grammars

      # Utilities
      # aider-chat  # Temporarily disabled due to texlive build issue
      btop
      exercism
      jira-cli-go
      k9s
      nil
      tenv
      terraform-ls
      amazon-ecr-credential-helper
      asdf-vm
      awscli2
      bat
      cachix
      cargo
      cmake
      diff-so-fancy
      fd
      flarectl-wrapped
      github-copilot-cli
      gnumake
      gnutls
      jq
      kubectl
      kubernetes-helm-wrapped
      kustomize
      libheif
      libtool
      # mosh
      nixpacks
      nmap
      pandoc
      ripgrep
      sqlite
      # terraform-docs # temporarily disabled due to build failure
      tree
      up

      # Fonts
      source-code-pro
      fira-code

      # Git
      ghq
      git
      git-crypt
      gnupg

      # Language Servers and runtimes
      bun
      gcc
      go
      gopls
      godef
      lua
      nixpkgs-fmt
      nodejs
      ruby # try init calls the unwrapped Ruby script from its shell function
      bash-language-server
      prettier
      typescript
      typescript-language-server
      vim-language-server
      yaml-language-server
      yarn

      #python
      python313
      python313Packages.ipython
      uv

      rust-analyzer

      # Get lazy
      lazycli
      lazydocker
      lazygit
      lazyjournal
      lazysql

      # Code review TUI
      inputs.tuicr.packages.${pkgs.stdenv.hostPlatform.system}.default

      # AWS Tools from flake inputs
      inputs.aws-tools.packages.${pkgs.stdenv.hostPlatform.system}.default
      inputs.aws-use-sso.packages.${pkgs.stdenv.hostPlatform.system}.default

      # Google Workspace CLI
      gws
    ]
    # AI quota tracker (endeavour also runs it as a service, see
    # modules/nixos/onwatch.nix). Linux only: on Darwin its Go tests call
    # `ps`, which the Nix build environment does not provide, so the build
    # fails.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      inputs.onwatch.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals (userApps.grove.enable or false) [
      inputs.grove.packages.${pkgs.stdenv.hostPlatform.system}.default
    ]
    ++ lib.optionals (userApps.google-cloud-sdk.enable or false) [
      (stable.google-cloud-sdk.withExtraComponents [
        stable.google-cloud-sdk.components.gke-gcloud-auth-plugin
      ])
    ]
    ++ lib.optionals (userApps.azure-cli.enable or false) [
      azure-cli
    ]
    ++ lib.optionals (userApps.sidecar.enable or false) [
      sidecar
    ]
    ++ lib.optionals (userApps.okta.enable or false) [
      okta-cli-client
    ]
    ++ lib.optionals (userApps.pup.enable or false) [
      pup # AI-agent-ready CLI for Datadog's observability platform
    ]
    ++ lib.optionals (userApps.namespace.enable or false) [
      namespace-cli # nsc/ns CLIs for Namespace (namespace.so)
    ]
    ++ lib.optionals (userApps.floai.enable or false) [
      inputs.floai.packages.${pkgs.stdenv.hostPlatform.system}.flo-cli
    ]
    ++ lib.optionals (userApps.codex.enable or false) [
      llm-agents.codex
      llm-agents.opencode
    ]
    ++ lib.optionals (userApps.t3code.enable or false) [
      # NixOS only. The Flo Mac uses the Homebrew cask in hosts/flomac so the
      # app can self-update. Do not enable this on Darwin: two t3 binaries.
      llm-agents.t3code
      llm-agents.t3code-desktop
    ]
    ++ lib.optionals (userApps.handy.enable or false) (
      [ llm-agents.handy ]
      # Handy needs a native Wayland typing tool; its Enigo/X11 fallback
      # cannot reliably type into Niri clients and can also prevent copying.
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ wtype ]
    )
    ++ lib.optionals (userApps.todoist.enable or false) [
      todoist
    ]
    ++ (
      if pkgs.stdenv.hostPlatform.isDarwin then
        [
          glibtool
        ]
      else
        [
          aws-sso-cli
          bibletime
          comixcursors
          deno
          dig
          # emacs
          emacsPackages.sqlite3
          glibc
          pavucontrol
          pinentry-gnome3
          remmina
          signal-cli # Signal CLI; Linux only, account linking is per host
          vial
          wally-cli
          xcb-util-cursor
          xclip

          # Flake input packages
          inputs.hubctl.packages.${pkgs.stdenv.hostPlatform.system}.default
          ghostty
        ]
    )
    ++ lib.optionals ((userApps.discord.enable or false) && pkgs.stdenv.hostPlatform.isLinux) [
      discord
    ]
    ++ lib.optionals ((userApps.signal.enable or false) && pkgs.stdenv.hostPlatform.isLinux) [
      (pkgs.symlinkJoin {
        name = "signal-desktop";
        paths = [ pkgs.signal-desktop ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/signal-desktop \
            --add-flags "--password-store=gnome-libsecret"
        '';
      })
    ]
    ++ lib.optionals ((userApps.obs.enable or false) && pkgs.stdenv.hostPlatform.isLinux) [
      obs-studio
    ]
    ++ lib.optionals (userApps.spotify.enable or false) [
      spotify
    ]
    ++ lib.optionals (userApps.slack.enable or false) [
      stable.slack
    ]
    ++ lib.optionals (userApps.freelens.enable or false) [
      freelens-bin
    ]
    ++ lib.optionals ((userApps.codiff.enable or false) && pkgs.stdenv.hostPlatform.isLinux) [
      codiff
    ]
    ++ lib.optionals (userApps.plannotator.enable or false) [
      plannotator
    ];

  programs.try = {
    enable = true;
    path = "~/dev/tries";
  };

  programs.gpg = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
  };

  # services.gpg-agent = { enable = pkgs.stdenv.hostPlatform.isLinux; };

  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "";
    };
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    enableCompletion = true;
    initContent = ''
      # Dumb terminal handling (Emacs TRAMP)
      if [[ $TERM = dumb ]]; then
        unset zle_bracketed_paste
        return
      fi

      # VSCode shell integration (disabled — vscode removed)
      # [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"

      # Nix daemon (Darwin only)
      if [[ "$(uname -s)" == "Darwin" ]] && [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi

      alias fd="fd --color=never"

      # try has no upstream completion script; offer commands and existing tries.
      _try_completion() {
        local dir
        local -a commands tries
        commands=(
          'clone:Clone a Git repository'
          'worktree:Create a Git worktree'
          '.:Create a worktree from the current directory'
          '--help:Show help'
        )
        if (( CURRENT == 2 )); then
          for dir in "$HOME${lib.removePrefix "~" config.programs.try.path}"/*(N/); do
            tries+=( "''${dir:t}" )
          done
          _describe -t commands 'try command' commands
          _describe -t tries 'experiment' tries
        elif [[ ''${words[2]} == worktree ]]; then
          _files -/
        fi
      }
      compdef _try_completion try

      # Load user secrets if present
      [ -f "$HOME/.env" ] && source "$HOME/.env"

      # source ''${vscodeScriptPath}  # disabled — vscode wrapper removed
      source ${borkedNsScriptPath}
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    # options = [ "--cmd cd" ];
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      sync_frequency = "10m";
      inline_height = 20;
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
    extensions = with pkgs; [
      gh-dash
      master.gh-stack
    ];
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = "openpgp";
    settings = {
      user = {
        name = "Jordan Garrison";
        email = "jordangarrison@users.noreply.github.com";
      };
      init.defaultBranch = "main";
      pull.ff = "only";
      merge.tool = "vimdiff";
      core.editor = "nvim";
      url."git@github.com:".insteadOf = "https://github.com/";
      github.user = "jordangarrison";
      gitlab.user = "jordan.andrew.garrison";
      alias = {
        co = "checkout";
        cob = "checkout -b";
        f = "fetch -p";
        c = "commit -m";
        p = "pull";
        pu = "!git push -u origin $(git rev-parse --abbrev-ref HEAD)";
        ba = "branch -a";
        bd = "branch -d";
        bD = "branch -D";
        dc = "diff --cached";
        dh = "diff ORIG_HEAD HEAD";
        dp = "diff HEAD^ HEAD";
        dop = "diff ORIG_HEAD^ ORIG_HEAD";
        st = "status -sb";
        a = "add -p";
        aa = "add --all";
        plog = "log --graph --pretty='format:%C(red)%d%C(reset) %C(yellow)%h%C(reset) %ar %C(green)%aN%C(reset) %s'";
        lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        tlog = "log --stat --since='1 Day Ago' --graph --pretty=oneline --abbrev-commit --date=relative";
        rank = "shortlog -sn --no-merges";
        bdm = "!git branch --merged | grep -v '*' | xargs -n 1 git branch -d";
        aliases = "!git config --list | grep alias";
      };
    };
  };

  programs.helix = {
    enable = true;
    extraPackages = with pkgs; [
      gopls
      gotools # goimports
      typescript-language-server
      rust-analyzer
      elixir-ls
      nil # nix LSP
      nixfmt
      marksman # markdown
    ];
    settings = {
      theme = "noctalia";
      editor = {
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
        file-picker = {
          hidden = false;
        };
        indent-guides = {
          render = true;
        };
        line-number = "relative";
        lsp = {
          display-messages = true;
        };
      };
    };
    languages = {
      language = [
        {
          name = "nix";
          auto-format = true;
          formatter.command = "nixfmt";
        }
        {
          name = "go";
          auto-format = true; # Runs goimports + gofmt on save via gopls
        }
        {
          name = "typescript";
          auto-format = true; # Format on save via typescript-language-server
        }
        {
          name = "rust";
          auto-format = true; # Runs rustfmt on save via rust-analyzer
        }
        {
          name = "elixir";
          auto-format = true; # Runs mix format on save via elixir-ls
        }
      ];
    };
  };

  programs.tmux = {
    enable = true;
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = {
      ignorecase = true;
    };
    extraConfig = ''
      set mouse=a
    '';
  };

  programs.vscode = {
    enable = userApps.vscode.enable or false;
    # package = pkgs.code-cursor;
  };

  programs.emacs = {
    enable = true;
    # Use pgtk variant on Linux for native Wayland support (fixes blurry text with fractional scaling)
    package = emacsPackage;
  };

  # Doom caches Emacs' absolute load-path, including Nix store paths, in an
  # init file keyed only by the Emacs version. Rebuild that cache when Nix
  # changes the store path without changing the version.
  home.activation.doomSyncOnEmacsChange = lib.mkIf pkgs.stdenv.hostPlatform.isLinux (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      doom_cli="${homeDirectory}/.emacs.d/bin/doom"
      doom_init="${homeDirectory}/.emacs.d/.local/etc/@/init.${lib.versions.majorMinor emacsPackage.version}.el"

      if [[ -x "$doom_cli" ]] \
        && { [[ ! -f "$doom_init" ]] || ! ${pkgs.gnugrep}/bin/grep -Fq "${emacsPackage}" "$doom_init"; }
      then
        echo "Doom cache references an old Emacs store path; running doom sync -U"
        if ! run ${pkgs.coreutils}/bin/env \
          PATH="${
            lib.makeBinPath [
              config.programs.emacs.finalPackage
              pkgs.bash
              pkgs.coreutils
              pkgs.findutils
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
            ]
          }:$PATH" \
          "$doom_cli" sync -U
        then
          echo "Doom sync failed; Emacs daemon may not start" >&2
        fi
      fi
    ''
  );

  programs.direnv = {
    enable = true;
    nix-direnv = {
      enable = true;
      # enableFlakes = true;
    };
  };

  # Alacritty - lightweight terminal that works well with tiling WMs and Niri clipboard
  programs.alacritty = {
    enable = true;
    settings = {
      general.live_config_reload = true;

      window = {
        decorations = "none";
        startup_mode = "Windowed";
        opacity = 0.80;
        padding = {
          x = 5;
          y = 5;
        };
      };

      font = {
        size = 10;
        normal = {
          family = "Source Code Pro";
          style = "Semibold";
        };
        bold = {
          family = "Source Code Pro";
          style = "Bold";
        };
        offset = {
          x = 0;
          y = 5;
        };
      };

      # Claude Code terminal integration - Shift+Enter for multiline input
      keyboard.bindings = [
        {
          key = "Return";
          mods = "Shift";
          chars = "\\n";
        }
      ];

      # Noctalia color theme (rose-pine inspired)
      colors = {
        primary = {
          foreground = "#e0def4";
          background = "#1f1d2e";
          dim_foreground = "#908caa";
          bright_foreground = "#e0def4";
        };
        cursor = {
          text = "#e0def4";
          cursor = "#524f67";
        };
        vi_mode_cursor = {
          text = "#e0def4";
          cursor = "#524f67";
        };
        search = {
          matches = {
            foreground = "#908caa";
            background = "#26233a";
          };
          focused_match = {
            foreground = "#191724";
            background = "#ebbcba";
          };
        };
        hints = {
          start = {
            foreground = "#908caa";
            background = "#1f1d2e";
          };
          end = {
            foreground = "#6e6a86";
            background = "#1f1d2e";
          };
        };
        line_indicator = {
          foreground = "None";
          background = "None";
        };
        footer_bar = {
          foreground = "#e0def4";
          background = "#1f1d2e";
        };
        selection = {
          text = "#e0def4";
          background = "#403d52";
        };
        normal = {
          black = "#26233a";
          red = "#eb6f92";
          green = "#31748f";
          yellow = "#f6c177";
          blue = "#9ccfd8";
          magenta = "#c4a7e7";
          cyan = "#ebbcba";
          white = "#e0def4";
        };
        bright = {
          black = "#6e6a86";
          red = "#eb6f92";
          green = "#31748f";
          yellow = "#f6c177";
          blue = "#9ccfd8";
          magenta = "#c4a7e7";
          cyan = "#ebbcba";
          white = "#e0def4";
        };
        dim = {
          black = "#6e6a86";
          red = "#eb6f92";
          green = "#31748f";
          yellow = "#f6c177";
          blue = "#9ccfd8";
          magenta = "#c4a7e7";
          cyan = "#ebbcba";
          white = "#e0def4";
        };
      };
    };
  };

  # FZF - fuzzy finder with shell integration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f";
    defaultOptions = [
      "--height 40%"
      "--border"
    ];
    fileWidget.command = "fd --type f";
    fileWidget.options = [ "--preview 'bat --style=numbers --color=always --line-range :500 {}'" ];
    changeDirWidget.command = "fd --type d";
    # Atuin already owns Ctrl-R in zsh; avoid installing a competing binding.
    historyWidget.zsh.command = "";
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      character = {
        success_symbol = "[➜](bold green) ";
        error_symbol = "[✗](bold red) ";
      };
      kubernetes.disabled = false;
      aws.symbol = "AWS ";
      gcloud.symbol = "GCP ";
    };
  };

  # Disable programs.ssh to avoid symlink permission issues
  # Using home.file approach with onChange instead

  home.shellAliases = {
    # Editors (use emacs-pgtk on Linux for native Wayland support)
    ec = "${emacsPackage}/bin/emacsclient -nw";
    e = "${emacsPackage}/bin/emacsclient -nw";
    ee = "${emacsPackage}/bin/emacsclient -nw $(${pkgs.fd}/bin/fd --type f | ${pkgs.fzf}/bin/fzf --preview '${pkgs.bat}/bin/bat --style=numbers --color=always --line-range :500 {}')";
    eg = "${emacsPackage}/bin/emacsclient";
    n = "nvim";
    view = "vim -R";

    # Shell/Navigation
    l = "ls -ltarh";
    ll = "ls -lh";
    la = "ls -a";
    lt = "ls -ltrh";
    dev = "cd $DEV_PATH";
    gogroot = "cd $(git rev-parse --show-toplevel)";

    # Git (OMZ git plugin provides gst, gco, gp, gl, gaa, etc.)
    c = "git commit -m";
    gss = "git status --short";
    pu = "git push -u origin $(git rev-parse --abbrev-ref HEAD)";
    p = "git pull";
    gd = "${pkgs.git}/bin/git diff --color | ${pkgs.diff-so-fancy}/bin/diff-so-fancy | less --tabs=4 -RFX";
    gdca = "${pkgs.git}/bin/git diff --color --cached | ${pkgs.diff-so-fancy}/bin/diff-so-fancy | less --tabs=4 -RFX";

    # Kubernetes
    k = "kubectl";
    kubeconfig = "$EDITOR ~/.kube/config";

    # AWS
    awsconfig = "$EDITOR ~/.aws/config";

    # Config editing
    zshconfig = "$EDITOR ~/.zshrc";
    sshconfig = "$EDITOR ~/.ssh/config";
    gitconfig = "$EDITOR ~/.gitconfig";

    # Utilities
    icanhazip = "curl -s https://api.ipify.org";
  };

  home.file = {
    # Pin ~/.local/bin/claude to the Nix-managed version to prevent auto-updater overwrites
    ".local/bin/claude".source = "${pkgs.llm-agents.claude-code}/bin/claude";

    # Claude Bridge provides Claude Code-backed models to Pi. Point it at the
    # Nix-managed CLI because the Agent SDK's bundled binary may not run on NixOS.
    ".pi/agent/claude-bridge.json".text = builtins.toJSON {
      askClaude.enabled = false;
      provider = {
        plan = "pro";
        longContextExtraUsage = false;
        strictMcpConfig = true;
        pathToClaudeCodeExecutable = "${pkgs.llm-agents.claude-code}/bin/claude";
      };
    };

    # SSH config with proper permissions fix
    ".ssh/config_source" = {
      source = ./configs/ssh/config;
      onChange = "cat ~/.ssh/config_source > ~/.ssh/config && chmod 600 ~/.ssh/config";
    };

    # doom emacs (linked directly to repo, not via Nix store)
    ".doom.d/init.el".source =
      config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/init.el";
    ".doom.d/packages.el".source =
      config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/packages.el";
    ".doom.d/config.org".source =
      config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/config.org";
    ".doom.d/themes".source =
      config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/tools/doom.d/themes";
    ".emacs.d/init.el".text = ''
      (load "default.el")
    '';

    # hyprland - now managed by configs/hypr/hyprland-home.nix module
    # Individual config files are symlinked via mkOutOfStoreSymlink for live editing

    # neovim configuration now handled by nvf
    # ".config/nvim/init.lua".source = ./tools/nvim/jag.lua;

    # Cobra CLI
    ".cobra.yaml".text = ''
      author: Jordan Garrison <dev@jordangarrison.dev>
      license: MIkT
      useViper: true
    '';

    # Claude Desktop
    # "Library/Application Support/Claude/claude_desktop_config.json" =
    #   lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    #     source = ./tools/claude-desktop/claude_desktop_config.json;
    #   };

    # Espanso
    ".config/espanso/match/base.yml" = lib.mkIf (!pkgs.stdenv.hostPlatform.isDarwin) {
      source = ./tools/espanso/match/base.yml;
    };
    "Library/Application Support/espanso/match/base.yml" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      source = ./tools/espanso/match/base.yml;
    };

    # LinearMouse
    # ".config/linearmouse/linearmouse.json" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    #   source = ./tools/linearmouse/linearmouse.json;
    # };

    # Wezterm (linked directly to repo, not via Nix store)
    ".config/wezterm/wezterm.lua".source =
      config.lib.file.mkOutOfStoreSymlink "${homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/tools/wezterm/wezterm.lua";

    # tmux-cht data files (script hardcodes ~/.tmux-cht-* paths)
    ".tmux-cht-languages".source = ./tools/scripts/tmux-cht-languages.txt;
    ".tmux-cht-commands".source = ./tools/scripts/tmux-cht-commands.txt;

    # gen-dynamic-wallpaper (macOS-specific, not packaged yet)
    ".local/bin/gen-dynamic-wallpaper" = {
      source = ./tools/scripts/gen-dynamic-wallpaper.sh;
      executable = true;
    };
  };

  # Handy daemon: keep a running instance so the compositor's
  # `handy --toggle-transcription` bind hits something. Pinning ExecStart to
  # the store path means home-manager restarts the unit on package bumps.
  # Linux-only: systemd.user.services doesn't exist in home-manager on darwin.
  systemd.user.services = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && (userApps.handy.enable or false)) {
    handy = {
      Unit = {
        Description = "Handy - push-to-talk speech-to-text";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.llm-agents.handy}/bin/handy --start-hidden";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
