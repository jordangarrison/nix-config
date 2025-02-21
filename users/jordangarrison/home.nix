{ config, pkgs, lib, ... }:

let
  vscodeScriptPath = pkgs.writeTextFile {
    name = "vscode";
    text = builtins.readFile ./tools/scripts/vscode.sh;
  };
  borkedNsScriptPath = pkgs.writeTextFile {
    name = "borked-ns";
    text = builtins.readFile ./tools/scripts/borked-ns.sh;
  };
in
{
  imports = [
    # ./tools/nvim/nvim.nix
  ];
  # nixpkgs.config.allowUnfree = true;
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
      # nix utilities
      nh
      devbox

      # Apps
      alacritty
      arandr
      emacs
      emacsPackages.sqlite3
      sqlite
      wezterm
      # doom-emacs

      # Utilities
      exercism
      gh
      helix
      k9s
      neovim
      nil
      tenv
      terraform-ls
      _1password-cli
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
      libtool
      # mosh
      nixpacks
      nmap
      pandoc
      ripgrep
      sqlite
      starship
      terraform-docs
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
      rust-analyzer
      yarn
    ] ++ (if pkgs.stdenv.isDarwin then
      [
        devenv
      ]
    else [
      aws-sso-cli
      comixcursors
      discord
      barrier
      deno
      dig
      glibc
      gnaural
      grip
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
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initExtra = ''
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

  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [ vim-airline ];
    settings = { ignorecase = true; };
    extraConfig = ''
      set mouse=a
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
    # doom emacs
    ".doom.d".source = ./tools/doom.d;
    ".emacs.d/init.el".text = ''
      (load "default.el")
    '';

    # neovim
    ".config/nvim/init.lua".source = ./tools/nvim/jag.lua;

    # Cobra CLI
    ".cobra.yaml".text = ''
      author: Jordan Garrison <dev@jordangarrison.dev>
      license: MIkT
      useViper: true
    '';

    # Alacritty
    ".config/alacritty/alacritty.yml".source = ./tools/alacritty/alacritty.yml;

    # Ghostty
    ".config/ghostty/config".source = ./tools/ghostty/config;

    # Wezterm
    ".config/wezterm/wezterm.lua".source = ./tools/wezterm/wezterm.lua;

    # Scripts
    ".local/bin/tmux-cht.sh".source = ./tools/scripts/tmux-cht.sh;
    ".tmux-cht-languages".source = ./tools/scripts/tmux-cht-languages.txt;
    ".tmux-cht-commands".source = ./tools/scripts/tmux-cht-commands.txt;

    # mac only
    ".config/linearmouse/linearmouse.json" = lib.mkIf pkgs.stdenv.isDarwin {
      source = ./tools/linearmouse/linearmouse.json;
    };

  };
}
