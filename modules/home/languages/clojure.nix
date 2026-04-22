{ config, lib, pkgs, ... }:

with lib;

{
  options.languages.clojure = {
    enable = mkEnableOption "Clojure development environment";
  };

  config = mkIf config.languages.clojure.enable {
    home.packages = with pkgs; [
      clojure
      leiningen
      clojure-lsp
      clj-kondo
      cljfmt
      babashka
      jet
    ];
  };
}
