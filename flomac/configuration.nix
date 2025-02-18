{ pkgs, lib, inputs, ... }: {
  environment.systemPackages = [
    pkgs.vim
  ];
  programs.zsh.enable = true;
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
}
