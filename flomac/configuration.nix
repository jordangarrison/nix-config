{ pkgs, lib, inputs, ... }: {
  environment.systemPackages = [
    pkgs.vim
    pkgs.git
  ];
  programs.zsh.enable = true;
  homebrew = {
    enable = true;
  };
  system.defaults = {
    dock = {
      autohide = true;
      orientation = "bottom";
      show-process-indicators = false;
    };
  };
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
}
