{ config, lib, pkgs, ... }:

with lib;

{
  options.languages.elixir = {
    enable = mkEnableOption "Elixir development environment";
  };

  config = mkIf config.languages.elixir.enable {
    home.packages = with pkgs; [
      elixir
      elixir-ls
      erlang
      rebar3
    ];
  };
}
