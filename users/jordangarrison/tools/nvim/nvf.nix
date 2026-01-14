{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  # Import the nvf Home Manager module
  imports = [ inputs.nvf.homeManagerModules.default ];

  programs.nvf = {
    enable = true;
    # your settings need to go into the settings attribute set
    # most settings are documented in the appendix
    settings = {
      vim = {
        # Suppress lspconfig deprecation warning until nvf migrates to vim.lsp.config
        # See: https://github.com/NotAShelf/nvf/issues/1225
        luaConfigPre = ''
          local notify = vim.notify
          vim.notify = function(msg, ...)
            if msg:match("The `require%(.*lspconfig.*)` \"framework\" is deprecated") then
              return
            end
            notify(msg, ...)
          end
        '';
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
          theme = "auto";
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
          name = "rose-pine";
          style = "main";
          transparent = true;
        };
        viAlias = true;
        vimAlias = true;
      };
    };
  };
}
