{ config, lib, pkgs, ... }:

let
  plugins = pkgs.vimPlugins;
  
  myPlugins = with plugins; [
      editorconfig-vim
      vim-airline
      vim-airline-themes
      vim-nix
      vim-surround
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
      { plugin = vim-startify; config = "let g:startify_change_to_vcs_root = 0"; }
  ];

  baseConfig = builtins.readFile ./config.vim;
  cocConfig = builtins.readFile ./coc.vim;
  cocSettings = builtins.toJSON (import ./coc-settings.nix);
  vimConfig = baseConfig + cocConfig + ''

    lua << EOF
    ${lib.strings.fileContents ./init.lua}
    EOF

  '';
  neovimPackages = with pkgs; [
    # Language Servers
    gopls
    rnix-lsp
    sumneko-lua-language-server
    nodePackages.bash-language-server
    nodePackages.vim-language-server
    nodePackages.yaml-language-server
    nodePackages.typescript
    nodePackages.typescript-language-server
    rust-analyzer
  ];
in {

  nixpkgs.overlays = [
    (import (builtins.fetchTarball {
      url = https://github.com/nix-community/neovim-nightly-overlay/archive/master.tar.gz;
    }))
  ];

  programs.neovim = {
    enable = true;
    extraConfig = vimConfig;
    package = pkgs.neovim-nightly;
    extraPackages = neovimPackages;
    plugins = myPlugins;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
  };

  xdg.configFile = {
    "nvim/coc-settings.json".text = cocSettings;
  };
}
