{ config, pkgs, lib, ... }:

let
  doom-emacs = pkgs.callPackage (builtins.fetchTarball {
    url =
      "https://github.com/nix-community/nix-doom-emacs/archive/master.tar.gz";
  }) {
    doomPrivateDir = ./tools/doom.d;

    dependencyOverrides = {
      "emacs-overlay" = (builtins.fetchTarball {
        url =
          "https://github.com/nix-community/emacs-overlay/archive/master.tar.gz";
      });
    };
    # Look at Issue #394 
    emacsPackagesOverlay = self: super: {
      gitignore-mode = pkgs.emacsPackages.git-modes;
      gitconfig-mode = pkgs.emacsPackages.git-modes;
    };
  };
in {
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

  home.packages = with pkgs;
    [
      # Apps
      gnaural
      doom-emacs

      # Utilities
      wally-cli
      httpie

      # Fonts
      source-code-pro
      fira-code

      # Git
      git
      git-crypt
      gnupg
      pinentry

      # Language Servers
      gcc
      gopls
      gocode
      godef
      rnix-lsp
      nodePackages.bash-language-server
      nodePackages.vim-language-server
      nodePackages.yaml-language-server
      nodePackages.typescript
      nodePackages.typescript-language-server
      rust-analyzer
      nixfmt
    ] ++ (if pkgs.stdenv.isDarwin then
      [ ]
    else [
      lens
      barrier
      spotify
      apple-music-electron
      slack
    ]

    );

  imports = (import ./tools);

  programs.gpg = { enable = pkgs.stdenv.isLinux; };

  services.gpg-agent = { enable = pkgs.stdenv.isLinux; };

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    initExtra = ''
      source ~/.dotfiles/zshrc
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

  programs.tmux = {
    enable = true;
    aggressiveResize = true;
    escapeTime = 0;
    historyLimit = 9999;
    terminal = "screen-256color";
    keyMode = "vi";
    extraConfig = ''
      # Escape key please stop hating me
      set -s escape-time 0

      # Split panes easily
      bind c new-window -c "#{pane_current_path}"
      bind -n M-'|' split-window -h -c "#{pane_current_path}"
      bind -n M-'\' split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Easier nav
      bind -n M-h select-pane -L
      bind -n M-l select-pane -R
      bind -n M-k select-pane -U
      bind -n M-j select-pane -D

      bind -n C-L next-window
      bind -n C-H previous-window

      bind -n M-H resize-pane -L 5
      bind -n M-L resize-pane -R 5
      bind -n M-K resize-pane -U 5
      bind -n M-J resize-pane -D 5
      bind -n M-M resize-pane -Z

      # mouse mode
      set -g mouse on

      # Design
      set -g status-position top
      set -g visual-activity off
      set -g visual-bell off
      set -g visual-silence off
      set -g bell-action none

      # Last window
      bind-key C-b last-window
    '';
  };

  programs.direnv = {
    enable = true;
    nix-direnv = {
      enable = true;
      # enableFlakes = true;
    };
  };

  home.file = {
    # Doom Emacs
    ".emacs.d/init.el".text = ''
      (load "default.el")
    '';

    # Alacritty
    ".config/alacritty/alacritty.yml".text = ''
      live_config_reload: true
      shell:
        program: zsh
        args:
          - -c
          - tmux
      font:
        normal:
          family: Source Code Pro
          style: Semibold
        bold:
          family: Source Code Pro
          style: Bold
        offset:
          x: 0
          y: 3
      # Window
      window:
        startup_mode: Maximized
        decorations: none
        padding:
          x: 5
          y: 5
      # Colors (substrata)
      colors:
        primary:
          background: '#191c25'
          foreground: '#b5b4c9'
        normal:
          black:   '#2e313d'
          red:     '#cf8164'
          green:   '#76a065'
          yellow:  '#ab924c'
          blue:    '#8296b0'
          magenta: '#a18daf'
          cyan:    '#659ea2'
          white:   '#b5b4c9'
        bright:
          black:   '#5b5f71'
          red:     '#fe9f7c'
          green:   '#92c47e'
          yellow:  '#d2b45f'
          blue:    '#a0b9d8'
          magenta: '#c6aed7'
          cyan:    '#7dc2c7'
          white:   '#f0ecfe'
    '';
    ".config/k9s/config.yml".text = ''
      ${lib.strings.fileContents ./tools/k9s/config.yml}
    '';
    ".config/k9s/skin.yml".text = ''
      ${lib.strings.fileContents ./tools/k9s/skin.yml}
    '';
  };
}
