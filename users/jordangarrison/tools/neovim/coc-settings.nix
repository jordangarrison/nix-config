{
  languageserver = {
    nix = {
      command = "rnix-lsp";
      filetypes = [ "nix" ];
    };
    go = {
      command = "gopls";
      rootPatterns = [ "go.mod" ];
      "trace.server" = "verbose";
      filetypes = [ "go" ];
    };
  };
}
