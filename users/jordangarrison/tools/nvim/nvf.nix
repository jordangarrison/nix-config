{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  # Import the nvf Home Manager module
  imports = [
    inputs.nvf.homeManagerModules.default
  ];

  programs.nvf = {
    enable = true;
    # your settings need to go into the settings attribute set
    # most settings are documented in the appendix
    settings = {
      vim = {
        assistant = {
          copilot.enable = true;
        };
        binds = {
          whichKey.enable = true;
          cheatsheet.enable = true;
        };
        git = {
          enable = true;
          gitsigns.enable = true;
          gitsigns.codeActions.enable = false;
        };
        languages = {
          enableTreesitter = true;
          enableExtraDiagnostics = true;
          bash.enable = true;
          go = {
            enable = true;
            lsp.enable = true;
          };
          html.enable = true;
          markdown.enable = true;
          nix.enable = true;
          python.enable = true;
          ruby.enable = pkgs.stdenv.isLinux;
          svelte.enable = true;
          tailwind.enable = true;
          ts.enable = true;
        };
        lsp = {
          enable = true;
          formatOnSave = true;
          lightbulb.enable = true;
          trouble.enable = true;
        };
        statusline.lualine = {
          enable = true;
          theme = "tokyonight";
        };
        telescope = {
          enable = true;
        };
        terminal = {
          toggleterm = {
            enable = true;
            lazygit.enable = true;
          };
        };
        theme = {
          enable = true;
          name = "tokyonight";
          style = "night";
        };
        viAlias = false;
        vimAlias = true;
      };
    };
  };
}
