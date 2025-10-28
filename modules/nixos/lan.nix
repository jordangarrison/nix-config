{ config, lib, pkgs, ... }:

{
  services.avahi = {
    enable = true;
    nssmdns = true;
  };
}
