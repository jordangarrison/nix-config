{ config, pkgs, ... }:

{
  # Docker
  virtualisation.docker.enable = true;
  # Docker services
  virtualisation.oci-containers = {
    backend = "docker";
    containers = {
      "jsoncrack" = {
        image = "shokohsc/jsoncrack";
        ports = [ "8888:8080" ];
      };
      "it-tools" = {
        image = "ghcr.io/corentinth/it-tools:latest";
        ports = [ "8889:80" ];
      };
    };
  };
}
