{ config, pkgs, lib, ... }:

let
  nixpkgs = import <nixpkgs> { };
  home-manager = import <home-manager> { inherit config lib pkgs; };
  unstable = import
    (fetchTarball "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz") {
      config = config.nixpkgs.config;
    };
in {
  imports = [
    # ./tools/nvim/nvim.nix
  ];
  nixpkgs.config.allowUnfree = true;
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username =
    if pkgs.stdenv.isLinux then "jordangarrison" else "jordan.garrison";
  # temporary hack for work
  home.homeDirectory = if pkgs.stdenv.isLinux then
    "/home/jordangarrison"
  else
    "/Users/jordan.garrison";

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

  nix = with pkgs; {
    package = nixFlakes;
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  home.packages = with pkgs;
    [
      # nix utilities
      unstable.nh

      # Apps
      alacritty
      arandr
      element-desktop
      emacs
      emacsPackages.sqlite3
      sqlite
      # doom-emacs

      # Utilities
      unstable.aws-sso-cli
      unstable.gptcommit
      unstable.gh
      unstable.helix
      unstable.lapce
      unstable.neovim
      unstable.nil
      unstable.k9s
      # unstable.okta-aws-cli
      _1password
      amazon-ecr-credential-helper
      awscli2
      bat
      cachix
      #devenv
      cargo
      cmake
      diff-so-fancy
      fd
      fzf
      git
      gnumake
      gnutls
      hstr
      httpie
      jq
      kubectl
      kubernetes-helm-wrapped
      kustomize
      libtool
      mosh
      nixpacks
      nmap
      pandoc
      ripgrep
      sqlite
      starship
      terraform
      terraform-docs
      tree
      up

      # Fonts
      source-code-pro
      fira-code

      # Git
      git
      git-crypt
      gnupg

      # Language Servers and runtimes
      unstable.terraform-ls
      unstable.bun
      gcc
      unstable.go
      unstable.gopls
      unstable.godef
      nixfmt
      unstable.nodejs
      # unstable.nodePackages.aws-cdk
      # nodePackages.cdk8s-cli
      # nodePackages.cdktf-cli
      nodePackages.bash-language-server
      nodePackages.prettier
      nodePackages.typescript
      nodePackages.typescript-language-server
      nodePackages.vim-language-server
      nodePackages.yaml-language-server
      rust-analyzer
      yarn
    ] ++ (if pkgs.stdenv.isDarwin then
      [ ]
    else [
      unstable.comixcursors
      unstable.discord
      barrier
      deno
      dig
      glibc
      gnaural
      jdk11
      lens
      obs-studio
      pavucontrol
      pinentry
      python39Full
      spotify
      slack
      wally-cli
      xcb-util-cursor
      xclip
    ]

    );

  programs.gpg = { enable = pkgs.stdenv.isLinux; };

  # services.gpg-agent = { enable = pkgs.stdenv.isLinux; };

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    syntaxHighlighting.enable = true;
    initExtra = ''
      source ~/.dotfiles/zshrc
      [[ "$TERM_PROGRAM" == "vscode" ]] && . "$(code --locate-shell-integration-path zsh)"
      # Nix
      if [[ "$(uname -s)" == "Darwin" ]] ; then
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
            . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi
      fi
      # End Nix

      alias fd="fd --color=never"
      # dumb TERM
      # [[ $TERM == dumb ]] && unsetopt zle && PS1='$ ' && return
    '';
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
    '';
  };

  # programs.neovim = {
  #   package = unstable.neovim;
  #   enable = true;
  #   viAlias = true;
  #   extraConfig = ''
  #     luafile ${./tools/nvim/jag.lua}
  #   '';
  # };

  # programs.tmux = {
  #   enable = true;
  #   aggressiveResize = true;
  #   escapeTime = 0;
  #   historyLimit = 9999;
  #   terminal = "screen-256color";
  #   keyMode = "vi";
  #   extraConfig = ''
  #     # Escape key please stop hating me
  #     set -s escape-time 0

  #     # Split panes easily
  #     bind c new-window -c "#{pane_current_path}"
  #     bind-key -r j run-shell "tmux neww ~/.local/bin/tmux-cht.sh"
  #     bind -n M-'|' split-window -h -c "#{pane_current_path}"
  #     bind -n M-'\' split-window -v -c "#{pane_current_path}"
  #     unbind '"'
  #     unbind %

  #     # Easier nav
  #     bind -n M-h select-pane -L
  #     bind -n M-l select-pane -R
  #     bind -n M-k select-pane -U
  #     bind -n M-j select-pane -D

  #     bind -n C-L next-window
  #     bind -n C-H previous-window

  #     bind -n M-H resize-pane -L 5
  #     bind -n M-L resize-pane -R 5
  #     bind -n M-K resize-pane -U 5
  #     bind -n M-J resize-pane -D 5
  #     bind -n M-M resize-pane -Z

  #     # mouse mode
  #     set -g mouse on

  #     # Design
  #     set -g status-position top
  #     set -g visual-activity off
  #     set -g visual-bell off
  #     set -g visual-silence off
  #     set -g bell-action none

  #     # Last window
  #     bind-key C-b last-window

  #     # renumber windows
  #     set-option -g renumber-windows on

  #     # Plugins
  #     run-shell ${pkgs.tmuxPlugins.resurrect.rtp}
  #     run-shell ${pkgs.tmuxPlugins.continuum.rtp}
  #   '';
  # };

  programs.direnv = {
    enable = true;
    nix-direnv = {
      enable = true;
      # enableFlakes = true;
    };
  };

  home.file = {
    # doom emacs
    ".doom.d/init.el".source = ./tools/doom.d/init.el;
    ".doom.d/packages.el".source = ./tools/doom.d/packages.el;
    ".doom.d/config.el".source = ./tools/doom.d/config.el;

    # neovim
    ".config/nvim/init.lua".source = ./tools/nvim/jag.lua;

    # Cobra CLI
    ".cobra.yaml".text = ''
      author: Jordan Garrison <dev@jordangarrison.dev>
      license: MIT
      useViper: true
    '';

    # Alacritty
    ".config/alacritty/alacritty.yml".source = ./tools/alacritty/alacritty.yml;

    # Doom emacs
    ".emacs.d/init.el".text = ''
      (load "default.el")
    '';

    # K9s
    # ".config/k9s/config.yml".source = ./tools/k9s/config.yml;
    # ".config/k9s/skin.yml".source = ./tools/k9s/skin.yml;

    # Btop
    # ".config/btop/btop.conf".source = ./tools/btop/btop.conf.yml;

    # Scripts
    ".local/bin/tmux-cht.sh".source = ./tools/scripts/tmux-cht.sh;
    ".tmux-cht-languages".source = ./tools/scripts/tmux-cht-languages.txt;
    ".tmux-cht-commands".source = ./tools/scripts/tmux-cht-commands.txt;
    # ".local/bin/okaws".source = ./tools/scripts/awsokta.sh;
    # ".config/nix/nix.conf".text = ''
    #   experimental-features = nix-command flakes
    # '';
  };
}
