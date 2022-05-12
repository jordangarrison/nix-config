{ config, pkgs, ... }:

{

  nixpkgs.config.allowUnfree = true;
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "jordangarrison";
  home.homeDirectory = "/home/jordangarrison";

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

  home.packages = with pkgs; [
    wally-cli
    spotify
    lens
    apple-music-electron
    barrier
    lens
    gnaural
    git
    git-crypt
    gnupg
    pinentry
    gopls
    rnix-lsp
    nodePackages.bash-language-server
    nodePackages.vim-language-server
    nodePackages.yaml-language-server
  ];

  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
  };

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins ; [ vim-airline ];
    settings = { ignorecase = true; };
    extraConfig= ''
      set mouse=a
    '';
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    plugins = with pkgs.vimPlugins; [ 
      editorconfig-vim
      vim-airline
      # vim-airline-themes
      vim-nix
      ctrlp-vim
      coc-yaml
      coc-tsserver
      coc-prettier
      coc-nvim
      coc-html
      coc-go
      coc-git
      coc-fzf
      coc-eslint
      coc-css
      vim-smoothie
      # which-key-nvim
    ];
    extraConfig = ''
      set mouse=a
      set timeoutlen=0

      " lua << EOF
      "   require("which-key").setup {
      "     -- Your config here
      "   }
      " EOF
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
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Easier nav
      bind -n M-h select-pane -L
      bind -n M-l select-pane -R
      bind -n M-k select-pane -U
      bind -n M-j select-pane -D

      bind -n M-H resize-pane -L
      bind -n M-L resize-pane -R
      bind -n M-K resize-pane -U
      bind -n M-J resize-pane -D

      # mouse mode
      set -g mouse on

      # Design
      set -g visual-activity off
      set -g visual-bell off
      set -g visual-silence off
      set -g bell-action none

      # Last window
      bind-key C-b last-window
    '';
  };

  home.file = {

    # Alacritty
    ".config/alacritty/alacritty.yml".text = ''
      shell:
        program: zsh
        args:
          - -c
          - tmux
      fonts:
        normal:
          family: Fira Code
          style: Regular
        bold:
          family: Fira Code
          style: Bold
        italic:
          family: Menlo
          style: Italic
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
      TERM: xterm-256color
    '';
  };
}
