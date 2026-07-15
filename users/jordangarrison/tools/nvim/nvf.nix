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
        autocomplete = {
          # corfu equivalent: as-you-type completion popup
          blink-cmp.enable = true;
        };
        binds = {
          whichKey = {
            enable = true;
            # Doom-style prefix labels
            register = {
              "<leader>b" = "buffer";
              "<leader>c" = "code";
              "<leader>f" = "file";
              "<leader>g" = "git";
              "<leader>h" = "help";
              "<leader>j" = "jag";
              "<leader>jn" = "nix";
              "<leader>o" = "open";
              "<leader>p" = "project";
              "<leader>q" = "quit";
              "<leader>s" = "search";
              "<leader>t" = "toggle";
              "<leader>w" = "window";
            };
          };
          cheatsheet.enable = true;
        };
        comments.comment-nvim.enable = true; # gc/gcc, like evil-commentary
        dashboard.dashboard-nvim.enable = true; # doom-dashboard equivalent
        filetree.neo-tree.enable = true; # treemacs equivalent
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
          typescript.enable = true;
        };
        lsp = {
          enable = true;
          formatOnSave = true;
          lightbulb.enable = true;
          trouble.enable = true;
          presets.tailwindcss-language-server.enable = true;
          # Doom lookup/code bindings
          mappings = {
            goToDefinition = "gd";
            listReferences = "gD";
            listImplementations = "gI";
            hover = "K";
            codeAction = "<leader>ca";
            renameSymbol = "<leader>cr";
            format = "<leader>cf";
            goToType = "<leader>ct";
            nextDiagnostic = "]e";
            previousDiagnostic = "[e";
          };
        };
        notes.todo-comments.enable = true; # hl-todo equivalent
        projects.project-nvim.enable = true; # projectile equivalent
        statusline.lualine = {
          enable = true;
          theme = "auto";
        };
        tabline.nvimBufferline = {
          enable = true; # doom tabs module
          mappings = {
            closeCurrent = "<leader>bd";
            cycleNext = "<leader>bn";
            cyclePrevious = "<leader>bp";
          };
        };
        telescope = {
          enable = true;
          mappings = {
            findFiles = "<leader>ff";
            buffers = "<leader>bb";
            liveGrep = "<leader>sp";
            helpTags = "<leader>hh";
            findProjects = "<leader>pp";
            resume = "<leader>'";
            treesitter = "<leader>si";
          };
        };
        terminal = {
          toggleterm = {
            enable = true;
            lazygit.enable = true; # magit stand-in on <leader>gg
          };
        };
        theme = {
          enable = true;
          name = "rose-pine";
          style = "main";
          transparent = true;
        };
        visuals = {
          indent-blankline.enable = true; # doom indent-guides
          nvim-web-devicons.enable = true;
        };
        viAlias = true;
        vimAlias = true;

        # Doom Emacs muscle memory
        keymaps = [
          # SPC SPC / SPC . / SPC , / SPC / — Doom's top-level verbs
          {
            key = "<leader><leader>";
            mode = "n";
            action = "<cmd>Telescope find_files<cr>";
            desc = "Find file in project";
          }
          {
            key = "<leader>.";
            mode = "n";
            action = "<cmd>Telescope find_files<cr>";
            desc = "Find file";
          }
          {
            key = "<leader>,";
            mode = "n";
            action = "<cmd>Telescope buffers<cr>";
            desc = "Switch buffer";
          }
          {
            key = "<leader>/";
            mode = "n";
            action = "<cmd>Telescope live_grep<cr>";
            desc = "Search project";
          }
          {
            key = "<leader>:";
            mode = "n";
            action = "<cmd>Telescope commands<cr>";
            desc = "M-x";
          }

          # file
          {
            key = "<leader>fs";
            mode = "n";
            action = "<cmd>w<cr>";
            desc = "Save file";
          }
          {
            key = "<leader>fr";
            mode = "n";
            action = "<cmd>Telescope oldfiles<cr>";
            desc = "Recent files";
          }
          {
            key = "<leader>fp";
            mode = "n";
            action = "<cmd>Telescope find_files cwd=~/dev/jordangarrison/nix-config<cr>";
            desc = "Find file in nix config";
          }

          # buffer
          {
            key = "<leader>bk";
            mode = "n";
            action = "<cmd>bd<cr>";
            desc = "Kill buffer";
          }
          {
            key = "]b";
            mode = "n";
            action = "<cmd>BufferLineCycleNext<cr>";
            desc = "Next buffer";
          }
          {
            key = "[b";
            mode = "n";
            action = "<cmd>BufferLineCyclePrev<cr>";
            desc = "Previous buffer";
          }

          # search
          {
            key = "<leader>ss";
            mode = "n";
            action = "<cmd>Telescope current_buffer_fuzzy_find<cr>";
            desc = "Search buffer";
          }

          # code
          {
            key = "<leader>cd";
            mode = "n";
            action = "<cmd>lua vim.lsp.buf.definition()<cr>";
            desc = "Jump to definition";
          }
          {
            key = "<leader>cD";
            mode = "n";
            action = "<cmd>lua vim.lsp.buf.references()<cr>";
            desc = "Jump to references";
          }
          {
            key = "<leader>cx";
            mode = "n";
            action = "<cmd>Trouble diagnostics toggle<cr>";
            desc = "List errors";
          }

          # help
          {
            key = "<leader>hk";
            mode = "n";
            action = "<cmd>Telescope keymaps<cr>";
            desc = "Search keymaps";
          }

          # open
          {
            key = "<leader>op";
            mode = "n";
            action = "<cmd>Neotree toggle<cr>";
            desc = "Project sidebar";
          }
          {
            key = "<leader>ot";
            mode = "n";
            action = "<cmd>ToggleTerm<cr>";
            desc = "Terminal";
          }

          # window: SPC w behaves as C-w, so all evil window commands carry over
          {
            key = "<leader>w";
            mode = "n";
            action = "<C-w>";
            desc = "window";
          }

          # quit
          {
            key = "<leader>qq";
            mode = "n";
            action = "<cmd>qa<cr>";
            desc = "Quit Neovim";
          }

          # toggle
          {
            key = "<leader>tl";
            mode = "n";
            action = "<cmd>set nu!<cr>";
            desc = "Toggle line numbers";
          }
          {
            key = "<leader>tw";
            mode = "n";
            action = "<cmd>set wrap!<cr>";
            desc = "Toggle word wrap";
          }

          # jag personal prefix, mirrors SPC j in Doom
          {
            key = "<leader>j/";
            mode = "n";
            action = "gcc";
            noremap = false;
            desc = "Comment line";
          }
          {
            key = "<leader>j/";
            mode = "v";
            action = "gc";
            noremap = false;
            desc = "Comment region";
          }
          {
            key = "<leader>jt";
            mode = "n";
            action = "<cmd>lua vim.o.background = vim.o.background == 'dark' and 'light' or 'dark'<cr>";
            desc = "Toggle theme";
          }
          {
            key = "<leader>js";
            mode = "n";
            action = ":!";
            silent = false;
            desc = "Shell command";
          }
          {
            key = "<leader>jc";
            mode = "n";
            action = "<cmd>TermExec direction=vertical size=80 cmd=claude<cr>";
            desc = "Claude Code";
          }
          {
            key = "<leader>jnb";
            mode = "n";
            action = "<cmd>TermExec cmd='nh os build . --no-nom'<cr>";
            desc = "nh os build .";
          }
          {
            key = "<leader>jnt";
            mode = "n";
            action = "<cmd>TermExec cmd='nh os test . --no-nom'<cr>";
            desc = "nh os test .";
          }
          {
            key = "<leader>jns";
            mode = "n";
            action = "<cmd>TermExec cmd='nh os switch . --no-nom'<cr>";
            desc = "nh os switch .";
          }
        ];
      };
    };
  };
}
