{ config, pkgs, ... }:

{
  systemd.tmpfiles.rules = [
    "d /home/jordangarrison/self-host 0775 jordangarrison docker"
    "d /home/jordangarrison/self-host/memos 0775 jordangarrison docker"
    "d /home/jordangarrison/self-host/archivebox 0775 jordangarrison docker"
  ];
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
      "memos" = {
        image = "neosmemo/memos:stable";
        ports = [ "5230:5230" ];
        volumes = [ "/home/jordangarrison/self-host/memos:/var/opt/memos" ];
      };
      "archivebox" = {
        image = "archivebox/archivebox:latest";
        ports = [ "8000:8000" ];
        volumes = [ "/home/jordangarrison/self-host/archivebox:/data" ];
      };
    };
  };
}
