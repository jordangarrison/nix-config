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
  emacsPackage = if pkgs.stdenv.isLinux then pkgs.emacs-pgtk else pkgs.emacs;
  # Live-checkout path for hand-authored agent content (see ./agents)
  agentsLive = "${config.home.homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/agents";
  piExtensions = pkgs.callPackage ../../packages/pi-extensions { };
in
{
  imports = [
    ./tools/nvim/nvf.nix
    ../../modules/home/acp-adapters
    ../../modules/home/languages
    ../../modules/home/pi
    ../../modules/home/herdr
    ../../modules/home/tuicr
    ../../modules/home/agent-skills
    ../../modules/home/agent-workspaces
    ../../modules/home/claude-code
    ../../modules/home/codex
  ];

  programs.agent-skills = {
    enable = true;
    skillsDir = ./skills;
    liveDir = "${config.home.homeDirectory}/dev/jordangarrison/nix-config/users/jordangarrison/skills";
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
      model = "fable";
      effortLevel = "high";
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
    };
  };

  programs.codex = {
    enable = true;
    instructionsFile = "${agentsLive}/AGENTS.md";
    rules."default.rules" = "${agentsLive}/codex/rules/default.rules";
    config = {
      approval_policy = "never";
      sandbox_mode = "danger-full-access";
      model = "gpt-5.6-sol";
      model_reasoning_effort = "high";
      plan_mode_reasoning_effort = "xhigh";
      personality = "pragmatic";
      approvals_reviewer = "user";
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
  ++ lib.optionals pkgs.stdenv.isDarwin [ "/opt/homebrew/bin" ];

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
    settings = {
      packages = [
        "${piExtensions}/lib/node_modules/jordangarrison-pi-extensions"
      ];
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
  };

  programs.acp-adapters = {
    enable = true;
  };

  # MCP servers written to ~/.config/mcp/mcp.json (read by pi-mcp-adapter,
  # and any other MCP client). Gated to the coding-agent hosts via herdr,
  # which is enabled on exactly the machines that run agents (endeavour,
  # opportunity, flomac) and off on the servers (voyager, discovery). Slack
  # is a remote OAuth endpoint hosted by Slack, so there is no local daemon
  # to run — pi runs the browser OAuth flow on first use and stores tokens in
  # its own keyring, not in this file. The clientId is Slack's public MCP
  # OAuth client, safe to commit.
  programs.mcp = {
    enable = userApps.herdr.enable or false;
    servers.slack = {
      url = "https://mcp.slack.com/mcp";
      oauth = {
        clientId = "1601185624273.8899143856786";
        # pi-mcp-adapter reads oauth.redirectUri (a full URI), not the
        # plugin's callbackPort field. Slack's pre-registered OAuth client
        # only accepts port 3118, so pin the exact registered redirect URI
        # — otherwise pi falls back to its default port 19876 and Slack
        # rejects it with "redirect_uri did not match any configured URIs".
        redirectUri = "http://localhost:3118/callback";
      };
    };
    # SRE/dev remote MCP servers. All OAuth with dynamic client registration,
    # so pi's default callback works and no clientId/redirectUri pin is needed
    # (unlike Slack's pre-registered client above). No secrets — tokens land in
    # pi's keyring, so these are safe in a public repo.
    servers.linear.url = "https://mcp.linear.app/mcp";
    servers.rootly.url = "https://mcp.rootly.com/mcp";
    # Confluence + Jira. Claude Code points at the older /v1/sse endpoint; this
    # uses the streamable-HTTP /v1/mcp one so the module's default type=http
    # applies. Same site as the jira CLI (flocasts.atlassian.net).
    servers.atlassian.url = "https://mcp.atlassian.com/v1/mcp";
    # scaleops' authorization-server metadata is self-inconsistent: it
    # advertises the AS as "https://mcp.scaleops.com" (no slash) but publishes
    # issuer "https://mcp.scaleops.com/" (slash), violating RFC 8414 §3.3. The
    # MCP SDK's one-directional slash tolerance can't bridge it and rejects the
    # server, so relax the issuer echo check for this server only (a config
    # bug on scaleops' side, not ours). Revisit/remove once they fix it.
    servers.scaleops = {
      url = "https://mcp.scaleops.com";
      oauth.skipIssuerMetadataValidation = true;
    };
  };

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
      master.devenv
      nh
      devbox

      # LLM Agents (available via overlay as pkgs.llm-agents.*)
      llm-agents.claude-code
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
    ++ lib.optionals (userApps.floai.enable or false) [
      inputs.floai.packages.${pkgs.stdenv.hostPlatform.system}.flo-cli
    ]
    ++ lib.optionals (userApps.codex.enable or false) [
      llm-agents.codex
      llm-agents.opencode
    ]
    ++ lib.optionals (userApps.handy.enable or false) [
      llm-agents.handy
    ]
    ++ lib.optionals (userApps.todoist.enable or false) [
      todoist
    ]
    ++ (
      if pkgs.stdenv.isDarwin then
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
          # gnaural was removed from unstable (unmaintained, gtk2); still in 25.11
          stable.gnaural
          grip
          pavucontrol
          pinentry-gnome3
          remmina
          vial
          wally-cli
          xcb-util-cursor
          xclip

          # Flake input packages
          inputs.hubctl.packages.${pkgs.stdenv.hostPlatform.system}.default
          ghostty
        ]
    )
    ++ lib.optionals ((userApps.discord.enable or false) && pkgs.stdenv.isLinux) [
      discord
    ]
    ++ lib.optionals ((userApps.signal.enable or false) && pkgs.stdenv.isLinux) [
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
    ++ lib.optionals ((userApps.obs.enable or false) && pkgs.stdenv.isLinux) [
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
    ++ lib.optionals ((userApps.codiff.enable or false) && pkgs.stdenv.isLinux) [
      codiff
    ]
    ++ lib.optionals (userApps.plannotator.enable or false) [
      plannotator
    ];

  programs.gpg = {
    enable = pkgs.stdenv.isLinux;
  };

  # services.gpg-agent = { enable = pkgs.stdenv.isLinux; };

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
      gh-stack
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
  home.activation.doomSyncOnEmacsChange = lib.mkIf pkgs.stdenv.isLinux (
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
    fileWidgetCommand = "fd --type f";
    fileWidgetOptions = [ "--preview 'bat --style=numbers --color=always --line-range :500 {}'" ];
    changeDirWidgetCommand = "fd --type d";
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
    #   lib.mkIf pkgs.stdenv.isDarwin {
    #     source = ./tools/claude-desktop/claude_desktop_config.json;
    #   };

    # Espanso
    ".config/espanso/match/base.yml" = lib.mkIf (!pkgs.stdenv.isDarwin) {
      source = ./tools/espanso/match/base.yml;
    };
    "Library/Application Support/espanso/match/base.yml" = lib.mkIf pkgs.stdenv.isDarwin {
      source = ./tools/espanso/match/base.yml;
    };

    # LinearMouse
    # ".config/linearmouse/linearmouse.json" = lib.mkIf pkgs.stdenv.isDarwin {
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
  systemd.user.services = lib.mkIf (pkgs.stdenv.isLinux && (userApps.handy.enable or false)) {
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
