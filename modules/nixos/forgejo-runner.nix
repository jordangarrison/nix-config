{ config, lib, pkgs, ... }:

{
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances = {
      docker = {
        enable = true;
        name = "endeavour-docker";
        url = "https://forgejo.jordangarrison.dev";
        tokenFile = "/var/lib/forgejo-runner-secrets/token";
        labels = [
          "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
          "ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
        ];
        settings = {
          runner.timeout = "3h";
          runner.shutdown_timeout = "3h";
          cache.enable = true;
        };
      };

      native = {
        enable = true;
        name = "endeavour-native";
        url = "https://forgejo.jordangarrison.dev";
        tokenFile = "/var/lib/forgejo-runner-secrets/token";
        labels = [ "native:host" ];
        hostPackages = with pkgs; [
          bash
          coreutils
          curl
          gawk
          git
          git-lfs
          gnused
          nodejs
          wget
          nix
        ];
        settings = {
          runner.timeout = "3h";
          runner.shutdown_timeout = "3h";
        };
      };
    };
  };

  # Grant Docker access to the docker runner instance
  systemd.services."gitea-runner-docker".serviceConfig.SupplementaryGroups = [ "docker" ];
}
