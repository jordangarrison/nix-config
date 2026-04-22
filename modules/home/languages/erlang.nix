{ config, lib, pkgs, ... }:

with lib;

{
  options.languages.erlang = {
    enable = mkEnableOption "Erlang/OTP development environment";
  };

  # Note: erlang-ls (the Erlang language server) is not packaged in nixpkgs.
  # Install it per-project via rebar3/escript if LSP features are needed, e.g.:
  #   git clone https://github.com/erlang-ls/erlang_ls
  #   cd erlang_ls && make && cp _build/default/bin/erlang_ls ~/.local/bin/
  # Doom's (erlang +lsp) module will auto-connect once the binary is on PATH.
  config = mkIf config.languages.erlang.enable {
    home.packages = with pkgs; [
      erlang
      rebar3
      erlfmt
      efmt
    ];
  };
}
