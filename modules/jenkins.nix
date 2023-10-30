{ config, pkgs, ... }:

{
  services.jenkins = {
    enable = true;
    port = 7878;
  };
}
