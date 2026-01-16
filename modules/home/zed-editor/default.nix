{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # Zed editor with Doom-style keybindings
  programs.zed-editor = {
    enable = true;

    # Extensions managed via nix-zed-extensions overlay
    # Note: These are initial extensions; Zed downloads them on first launch
    extensions = [
      "nix"
      "toml"
      "html"
      "dockerfile"
      "git-firefly"
    ];

    userSettings = {
      # Core settings
      vim_mode = true;
      theme = {
        mode = "system";
        dark = "Rosé Pine";
        light = "Rosé Pine Dawn";
      };

      # Font configuration
      buffer_font_family = "FiraCode Nerd Font";
      buffer_font_size = 14;
      ui_font_family = "FiraCode Nerd Font";
      ui_font_size = 14;

      # Editor behavior
      tab_size = 2;
      format_on_save = "on";
      relative_line_numbers = false;
      show_wrap_guides = true;

      # Terminal
      terminal = {
        font_family = "FiraCode Nerd Font";
        font_size = 13;
      };

      # AI - Using Claude Code via terminal instead of built-in assistant
      assistant = {
        enabled = false;
      };

      # Git gutter
      git = {
        git_gutter = "tracked_files";
      };
    };

    userKeymaps = [
      # Vim normal mode with space leader - Full Doom-style bindings
      {
        context = "vim_mode == normal";
        bindings = {
          # ========== Files (SPC f) ==========
          "space f f" = "file_finder::Toggle";
          "space f r" = "projects::OpenRecent";
          "space f s" = "workspace::Save";
          "space f S" = "workspace::SaveAll";
          "space f y" = "editor::CopyFileName";
          "space f o" = "pane::SplitRight";

          # ========== Buffers (SPC b) ==========
          "space b b" = "tab_switcher::Toggle";
          "space b d" = "pane::CloseActiveItem";
          "space b k" = "pane::CloseActiveItem";
          "space b n" = "pane::ActivateNextItem";
          "space b p" = "pane::ActivatePreviousItem";
          "space b s" = "workspace::Save";
          "space b N" = "workspace::NewFile";

          # ========== Windows (SPC w) ==========
          "space w v" = "pane::SplitRight";
          "space w s" = "pane::SplitDown";
          "space w d" = "pane::CloseAllItems";
          "space w h" = "workspace::ActivatePaneLeft";
          "space w j" = "workspace::ActivatePaneDown";
          "space w k" = "workspace::ActivatePaneUp";
          "space w l" = "workspace::ActivatePaneRight";
          "space w m" = "workspace::ToggleZoom";
          "space w o" = "pane::CloseOtherItems";
          "space w w" = "workspace::ActivateNextPane";

          # ========== Search (SPC s) ==========
          "space s s" = "buffer_search::Deploy";
          "space s p" = "pane::DeploySearch";
          "space s i" = "outline::Toggle";
          "space s I" = "project_symbols::Toggle";
          "space s r" = "search::SelectAllMatches";
          "space /" = "pane::DeploySearch";

          # ========== Project (SPC p) ==========
          "space p p" = "projects::OpenRecent";
          "space p f" = "file_finder::Toggle";
          "space p t" = "project_panel::ToggleFocus";
          "space p r" = "search::SelectAllMatches";

          # ========== Git (SPC g) ==========
          "space g g" = "git_panel::ToggleFocus";
          "space g d" = "editor::ToggleSelectedDiffHunks";
          "space g b" = "git::Blame";
          "space g [" = "editor::GoToPreviousHunk";
          "space g ]" = "editor::GoToNextChange";

          # ========== Code/LSP (SPC c) ==========
          "space c a" = "editor::ToggleCodeActions";
          "space c d" = "editor::GoToDefinition";
          "space c D" = "editor::GoToDeclaration";
          "space c r" = "editor::FindAllReferences";
          "space c R" = "editor::Rename";
          "space c f" = "editor::Format";
          "space c x" = "diagnostics::Deploy";
          "space c k" = "editor::Hover";
          "space c i" = "editor::GoToImplementation";
          "space c t" = "editor::GoToTypeDefinition";

          # ========== Toggle (SPC t) ==========
          "space t l" = "editor::ToggleLineNumbers";
          "space t w" = "editor::ToggleSoftWrap";
          "space t i" = "editor::ToggleIndentGuides";
          "space t z" = "workspace::ToggleCenteredLayout";
          "space t t" = "terminal_panel::ToggleFocus";

          # ========== Open (SPC o) ==========
          "space o t" = "terminal_panel::ToggleFocus";
          "space o p" = "project_panel::ToggleFocus";

          # ========== Help (SPC h) ==========
          "space h k" = "zed::OpenKeymap";
          "space h h" = "command_palette::Toggle";

          # ========== Custom Jordan (SPC j) ==========
          "space j k" = "editor::Hover";
          "space j t" = "theme_selector::Toggle";
          "space j /" = "editor::ToggleComments";
        };
      }
      # Global context bindings (work everywhere)
      {
        bindings = {
          "ctrl-`" = "terminal_panel::ToggleFocus";
        };
      }
    ];
  };
}
