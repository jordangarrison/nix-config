# Yazi terminal file manager
{ pkgs, ... }:

{
  # Runtime dependency of the drag plugin (called as bare `ripdrag`)
  home.packages = [ pkgs.ripdrag ];

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";
    plugins = {
      drag = pkgs.yaziPlugins.drag;
    };
    keymap.mgr.prepend_keymap = [
      {
        on = [ "<C-d>" ];
        run = "plugin drag";
        desc = "Drag selected files";
      }
    ];
  };
}
