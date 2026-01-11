{ config, lib, pkgs, ... }:

with lib;

{
  options.languages.ruby = {
    enable = mkEnableOption "Ruby and Rails development environment";
  };

  config = mkIf config.languages.ruby.enable {
    home.packages = with pkgs; [
      ruby
      rails-new
      rubyfmt
      ruby-lsp
      rubyPackages.pry
      rubyPackages.rails
      rubyPackages.solargraph
    ];
  };
}
