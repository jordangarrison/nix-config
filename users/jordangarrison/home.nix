{ config, pkgs, lib, ... }:

let
  unstable = import
    (fetchTarball "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz")
    {
      config = config.nixpkgs.config;
    };
  ###################################################################
  # Currently broken, need to get this updates with new doom cli
  ###################################################################
  # doom-emacs = pkgs.callPackage
  #   (builtins.fetchTarball {
  #     url =
  #       "https://github.com/nix-community/nix-doom-emacs/archive/master.tar.gz";
  #   })
  #   {
  #     doomPrivateDir = ./tools/doom.d;

  #     # This is currently broken so commenting out
  #     # dependencyOverrides = {
  #     #   "emacs-overlay" = (builtins.fetchTarball {
  #     #     url =
  #     #       "https://github.com/nix-community/emacs-overlay/archive/master.tar.gz";
  #     #   });
  #     # };
  #     # Look at Issue #394
  #     emacsPackagesOverlay = self: super: {
  #       gitignore-mode = pkgs.emacsPackages.git-modes;
  #       gitconfig-mode = pkgs.emacsPackages.git-modes;
  #     };
  #   };
  ###################################################################
in
{
  nixpkgs.config.allowUnfree = true;
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username =
    if pkgs.stdenv.isLinux then "jordangarrison" else "jordan.garrison";
  # temporary hack for work
  home.homeDirectory =
    if pkgs.stdenv.isLinux then
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
      alacritty
      arandr
      element-desktop
      dbeaver
      # doom-emacs

      # Utilities
      _1password
      aws
      bat
      cargo
      diff-so-fancy
      fd
      fzf
      git
      gnutls
      hstr
      httpie
      jq
      k9s
      mosh
      nmap
      pandoc
      ripgrep
      sqlite
      starship
      tree

      # Fonts
      source-code-pro
      fira-code

      # Git
      git
      git-crypt
      gnupg
      pinentry

      # Language Servers and runtimes
      gcc
      go
      gocode
      gopls
      godef
      nixfmt
      nodePackages.bash-language-server
      nodePackages.vim-language-server
      nodePackages.yaml-language-server
      nodePackages.typescript
      nodePackages.typescript-language-server
      rnix-lsp
      rust-analyzer
    ] ++ (if pkgs.stdenv.isDarwin then
      [
        unstable.nodejs
      ]
    else [
      unstable.comixcursors
      unstable.discord
      apple-music-electron
      barrier
      deno
      dig
      gnaural
      lens
      obs-studio
      pavucontrol
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
    enableSyntaxHighlighting = true;
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
      bind-key -r j run-shell "tmux neww ~/.local/bin/tmux-cht.sh"
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

      # renumber windows
      set-option -g renumber-windows on

      # Plugins
      run-shell ${pkgs.tmuxPlugins.resurrect.rtp}
      run-shell ${pkgs.tmuxPlugins.continuum.rtp}
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
  };
}
