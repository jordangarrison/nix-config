{ config, pkgs, lib, ... }:

let
  unstable = import
    (fetchTarball "https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz")
    { };
  doom-emacs = pkgs.callPackage (builtins.fetchTarball {
    url =
      "https://github.com/nix-community/nix-doom-emacs/archive/master.tar.gz";
  }) {
    doomPrivateDir = ./tools/doom.d;

    # This is currently broken so commenting out
    # dependencyOverrides = {
    #   "emacs-overlay" = (builtins.fetchTarball {
    #     url =
    #       "https://github.com/nix-community/emacs-overlay/archive/master.tar.gz";
    #   });
    # };
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
      unstable.dbeaver
      alacritty
      arandr
      element-desktop
      doom-emacs

      # Utilities
      _1password
      aws
      bat
      cargo
      diff-so-fancy
      fzf
      git
      hstr
      httpie
      jq
      k9s
      mosh
      ripgrep
      starship
      wally-cli

      # Fonts
      source-code-pro
      fira-code

      # Git
      git
      git-crypt
      gnupg
      pinentry

      # Language Servers and runtimes
      deno
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
      [ unstable.nodejs ]
    else [
      unstable.comixcursors
      apple-music-electron
      barrier
      dig
      discord
      gnaural
      lens
      obs-studio
      pavucontrol
      python39Full
      redshift
      spotify
      slack
      xcb-util-cursor
      xclip
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
    # Doom Emacs
    ".emacs.d/init.el".text = ''
      (load "default.el")
    '';

    # Cursors for AwesomeWM
    ".Xresources".text = ''
      Xcursor.size = 24
    '';

    ".config/gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-application-prefer-dark-theme=0
      gtk-theme-name=Adwaita-dark
      gtk-icon-theme-name=Adwaita
      gtk-font-name=Sans 10
      gtk-cursor-theme-size=24
      gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
      gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
      gtk-button-images=0
      gtk-menu-images=0
      gtk-enable-event-sounds=1
      gtk-enable-input-feedback-sounds=1
      gtk-xft-antialias=1
      gtk-xft-hinting=1
      gtk-xft-hintstyle=hintslight
      gtk-xft-rgba=rgb
      gtk-cursor-theme-name=Adwaita
    '';

    # Alacritty
    ".config/alacritty/alacritty.yml".source = ./tools/alacritty/alacritty.yml;

    # Awesome
    ".config/awesome/rc.lua".source = ./tools/awesome/rc.lua;
    ".config/awesome/background.jpg".source = ./tools/awesome/background.jpg;
    ".config/awesome/awesome-wm-widgets".source = pkgs.fetchFromGitHub {
      owner = "streetturtle";
      repo = "awesome-wm-widgets";
      rev = "83914c91c86eee4d70120a2849e752f7762908d7";
      sha256 = "0w0y11qzp287n8asr3ml0n05lxja77cc8cl8q5n2drxywpb675aw";
    };

    # K9s
    ".config/k9s/config.yml".source = ./tools/k9s/config.yml;
    ".config/k9s/skin.yml".source = ./tools/k9s/skin.yml;

    # Btop
    ".config/btop/btop.conf".source = ./tools/btop/btop.conf.yml;

    # Redshift
    ".config/redshift.conf".source = ./tools/redshift/redshift.conf;

    # Scripts
    ".local/bin/tmux-cht.sh".source = ./tools/scripts/tmux-cht.sh;
    ".tmux-cht-languages".source = ./tools/scripts/tmux-cht-languages.txt;
    ".tmux-cht-commands".source = ./tools/scripts/tmux-cht-commands.txt;
  };
}
