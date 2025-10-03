{ config, pkgs, lib, username, homeDirectory, inputs, ... }:

let
  vscodeScriptPath = pkgs.writeTextFile {
    name = "vscode";
    text = builtins.readFile ./tools/scripts/vscode.sh;
  };
  borkedNsScriptPath = pkgs.writeTextFile {
    name = "borked-ns";
    text = builtins.readFile ./tools/scripts/borked-ns.sh;
  };
  binauralBeatsScriptPath = pkgs.writeTextFile {
    name = "binarual-beats";
    text = builtins.readFile ./tools/scripts/binaural-beats.sh;
  };
in {
  imports = [ ./tools/nvim/nvf.nix ];

  # nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Enable claude-code from the claude-code-nix flake
  programs.claude-code = {
    enable = true;
    package = inputs.claude-code.packages.${pkgs.system}.default;
  };

  home.packages = with pkgs;
    [
      # nix utilities
      nh
      devbox

      # Apps
      alacritty
      arandr
      mailspring
      sqlite
      todoist
      warp-terminal
      wezterm
      zed-editor
      # doom-emacs

      # Utilities
      # aider-chat  # Temporarily disabled due to texlive build issue
      btop
      exercism
      helix
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
      fzf
      git
      gnumake
      gnutls
      # gptcommit
      hstr
      httpie
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
      starship
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
      terraform-ls
      bun
      gcc
      gleam
      erlang
      rebar3
      go
      gopls
      godef
      lua
      nixfmt-classic
      nixpkgs-fmt
      nodejs
      nodePackages.bash-language-server
      nodePackages.prettier
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.vim-language-server
      nodePackages.yaml-language-server

      #python
      python313
      python313Packages.ipython

      #ruby
      ruby
      rails-new
      ruby-lsp
      rubyPackages.pry
      rubyPackages.rails
      # rubyPackages.railties # Broken in latest update
      rubyPackages.solargraph
      rust-analyzer
      uv
      yarn

      # AWS Tools from flake inputs
      inputs.aws-tools.packages.${pkgs.system}.default
      inputs.aws-use-sso.packages.${pkgs.system}.default
      inputs.hubctl.packages.${pkgs.system}.default

      # GCP
      (google-cloud-sdk.withExtraComponents
        [ google-cloud-sdk.components.gke-gcloud-auth-plugin ])
    ] ++ (if pkgs.stdenv.isDarwin then [
      devenv
      glibtool
    ] else [
      aws-sso-cli
      bibletime
      comixcursors
      copyq
      discord
      deno
      dig
      # emacs
      emacsPackages.sqlite3
      glibc
      gnaural
      grip
      obs-studio
      pavucontrol
      pinentry
      remmina
      rubyfmt
      slack
      vial
      wally-cli
      xcb-util-cursor
      xclip

      # Flake input packages
      inputs.warp-preview.packages.${pkgs.system}.default
    ]);

  programs.gpg = { enable = pkgs.stdenv.isLinux; };

  # services.gpg-agent = { enable = pkgs.stdenv.isLinux; };

  programs.zsh = {
    enable = true;
    oh-my-zsh = { enable = true; };
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = ''
      source ~/.dotfiles/zshrc
      [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"
      # Nix
      if [[ "$(uname -s)" == "Darwin" ]] ; then
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
        export PATH=/opt/homebrew/bin:$PATH
      fi
      # End Nix

      alias fd="fd --color=never"
      # dumb TERM
      # [[ $TERM == dumb ]] && unsetopt zle && PS1='$ ' && return

      eval "$(atuin init zsh)"

      source ${vscodeScriptPath}
      source ${borkedNsScriptPath}
    '';
  };

  programs.atuin = {
    enable = true;
    settings = {
      sync_frequency = "10m";
      inline_height = 20;
    };
  };

  programs.gh = {
    enable = true;
    settings = { git_protocol = "ssh"; };
    extensions = with pkgs; [ gh-copilot gh-dash ];
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
    '';
  };

  programs.vscode = {
    enable = true;
    package = pkgs.code-cursor;
  };

  programs.emacs = { enable = true; };

  programs.direnv = {
    enable = true;
    nix-direnv = {
      enable = true;
      # enableFlakes = true;
    };
  };

  # Disable programs.ssh to avoid symlink permission issues
  # Using home.file approach with onChange instead

  home.shellAliases = {
    # Emacs Aliases
    ec = "${pkgs.emacs}/bin/emacsclient -nw";
    e = "${pkgs.emacs}/bin/emacsclient -nw";
    ee =
      "${pkgs.emacs}/bin/emacsclient -nw $(${pkgs.fd}/bin/fd --type f | ${pkgs.fzf}/bin/fzf --preview '${pkgs.bat}/bin/bat --style=numbers --color=always --line-range :500 {}')";
    eg = "${pkgs.emacs}/bin/emacsclient";

    # Shell aliases
    l = "ls -ltarh";
    ll = "ls -lh";
    la = "ls -a";

    # Git aliases
    c = "git commit -m";
    gss = "git status --short";
    pu = "git push -u origin $(git rev-parse --abbrev-ref HEAD)";
    p = "git pull";
    gd =
      "${pkgs.git}/bin/git diff --color | ${pkgs.diff-so-fancy}/bin/diff-so-fancy | less --tabs=4 -RFX";
    gdca =
      "${pkgs.git}/bin/git diff --color --cached | ${pkgs.diff-so-fancy}/bin/diff-so-fancy | less --tabs=4 -RFX";
  };

  home.file = {
    # SSH config with proper permissions fix
    ".ssh/config_source" = {
      source = ./configs/ssh/config;
      onChange =
        "cat ~/.ssh/config_source > ~/.ssh/config && chmod 600 ~/.ssh/config";
    };

    # doom emacs
    # ".doom.d".source = ./tools/doom.d;
    ".doom.d/init.el".source = tools/doom.d/init.el;
    ".doom.d/packages.el".source = tools/doom.d/packages.el;
    ".doom.d/config.org".source = tools/doom.d/config.org;
    ".emacs.d/init.el".text = ''
      (load "default.el")
    '';

    # hyprland
    ".config/hypr".source = ./configs/hypr;

    # neovim configuration now handled by nvf
    # ".config/nvim/init.lua".source = ./tools/nvim/jag.lua;

    # Cobra CLI
    ".cobra.yaml".text = ''
      author: Jordan Garrison <dev@jordangarrison.dev>
      license: MIkT
      useViper: true
    '';

    # Alacritty
    ".config/alacritty/alacritty.toml".source =
      ./tools/alacritty/alacritty.toml;

    # Claude Desktop
    # "Library/Application Support/Claude/claude_desktop_config.json" =
    #   lib.mkIf pkgs.stdenv.isDarwin {
    #     source = ./tools/claude-desktop/claude_desktop_config.json;
    #   };

    # Espanso
    ".config/espanso/match/base.yml" = lib.mkIf (!pkgs.stdenv.isDarwin) {
      source = ./tools/espanso/match/base.yml;
    };
    "Library/Application Support/espanso/match/base.yml" =
      lib.mkIf pkgs.stdenv.isDarwin {
        source = ./tools/espanso/match/base.yml;
      };

    # Ghostty
    ".config/ghostty/config".source = ./tools/ghostty/config;

    # LinearMouse
    # ".config/linearmouse/linearmouse.json" = lib.mkIf pkgs.stdenv.isDarwin {
    #   source = ./tools/linearmouse/linearmouse.json;
    # };

    # Wezterm
    ".config/wezterm/wezterm.lua".source = ./tools/wezterm/wezterm.lua;

    # Scripts
    ".local/bin/tmux-cht.sh".source = ./tools/scripts/tmux-cht.sh;
    ".tmux-cht-languages".source = ./tools/scripts/tmux-cht-languages.txt;
    ".tmux-cht-commands".source = ./tools/scripts/tmux-cht-commands.txt;
    ".local/bin/gen-dynamic-wallpaper".source =
      ./tools/scripts/gen-dynamic-wallpaper.sh;
    ".local/bin/myip".source = ./tools/scripts/myip.sh;
  };
}
