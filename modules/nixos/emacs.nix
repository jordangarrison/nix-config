{ config, lib, pkgs, ... }:

{
  services.emacs = { enable = true; };
  environment.systemPackages = with pkgs; [ wl-clipboard xclip ];
}
