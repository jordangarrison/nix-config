{ pkgs, lib, ... }:
let
  nixvim = import (builtins.fetchGit {
    url = "https://github.com/nix-community/nixvim";
    ref = "nixos-23.11";
  });
in
{
  imports = [
    nixvim.homeManagerModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    options = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
    };

    globals.mapleader = " "; # set the leader key to space

    keymaps = [
      {
        mode = "n";
        key = "<leader>fs";
        action = "<cmd>w<CR>";
      }
    ];

    plugins = {
      direnv.enable = true;
      lightline.enable = true;
    };
    extraPlugins = with pkgs.vimPlugins; [
      vim-nix
      codeium-vim
    ];
  };
}
