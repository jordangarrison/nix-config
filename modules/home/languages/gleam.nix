{ config, lib, pkgs, ... }:

with lib;

{
  options.languages.gleam = {
    enable = mkEnableOption "Gleam and Erlang development environment";
  };

  config = mkIf config.languages.gleam.enable {
    home.packages = with pkgs; [
      gleam
      erlang
      rebar3
    ];
  };
}
