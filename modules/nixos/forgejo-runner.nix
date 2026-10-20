{ config, lib, pkgs, ... }:

let
  # UUIDs come from the runners' original registrations
  # (/var/lib/gitea-runner/<instance>/.runner). The matching tokens live in
  # /var/lib/forgejo-runner-secrets/<instance>-token, outside the store.
  connection = uuid: {
    url = "https://forgejo.jordangarrison.dev";
    inherit uuid;
  };
in
{
  services.forgejo-runner.instances = {
    docker = {
      enable = true;
      settings = {
        server.connections.default = connection "e60797b0-3d95-4c2d-aa6d-b8a9322ad487";
        runner.labels = [
          "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
          "ubuntu-22.04:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
        ];
        runner.timeout = "3h";
        runner.shutdown_timeout = "3h";
        runner.capacity = 4;
        cache.enable = true;
      };
      secrets.server.connections.default.token_url = "/var/lib/forgejo-runner-secrets/docker-token";
    };

    native = {
      enable = true;
      settings = {
        server.connections.default = connection "242c7e13-d2f0-49f6-8d47-aad9524fa5cb";
        runner.labels = [ "native:host" ];
        runner.timeout = "3h";
        runner.shutdown_timeout = "3h";
      };
      secrets.server.connections.default.token_url = "/var/lib/forgejo-runner-secrets/native-token";
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
    };
  };
}
