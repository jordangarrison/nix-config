{ config, pkgs, ... }:

# Executor is on Docker's default bridge. Maple stays on loopback and its ingest
# key stays in the host collector; this unauthenticated receiver is bridge-only.
let
  bridgeAddress = "172.17.0.1";
  bridgeSubnet = "172.17.0.0/16";
  port = 4319;
  ingressRules = pkgs.writeText "executor-otlp-ingress.nft" ''
    add table inet executor_otlp
    flush table inet executor_otlp
    table inet executor_otlp {
      chain input {
        type filter hook input priority -10; policy accept;
        ip daddr ${bridgeAddress} tcp dport ${toString port} jump ingest
      }
      chain ingest {
        iifname "docker0" ip saddr ${bridgeSubnet} counter accept
        counter reject with tcp reset
      }
    }
  '';
in
{
  services.opentelemetry-collector.settings = {
    receivers."otlp/executor".protocols.http.endpoint = "${bridgeAddress}:${toString port}";
    processors."resource/executor".attributes = [
      { key = "host.name"; value = config.networking.hostName; action = "upsert"; }
      { key = "service.namespace"; value = "executor"; action = "upsert"; }
      { key = "deployment.environment.name"; value = "homelab"; action = "upsert"; }
    ];
    service.pipelines = builtins.listToAttrs (map (signal: {
      name = "${signal}/executor";
      value = {
        receivers = [ "otlp/executor" ];
        processors = [ "memory_limiter" "resource/executor" "batch" ];
        exporters = [ "otlphttp/maple" ];
      };
    }) [ "traces" "logs" "metrics" ]);
  };

  # Two layers. The host firewall opens the port on docker0 only. The
  # independent nftables input hook below does not depend on the host
  # firewall: Docker's DOCKER-USER chain only filters forwarding, and an
  # iptables INPUT rule could be bypassed if another service later inserts an
  # ACCEPT ahead of it. Each layer must accept for a packet to get through.
  networking.firewall.interfaces.docker0.allowedTCPPorts = [ port ];

  systemd.services.executor-otlp-ingress = {
    description = "Restrict Executor OTLP ingest to the Docker bridge";
    requires = [ "docker.service" ];
    after = [ "docker.service" ];
    before = [ "opentelemetry-collector.service" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    # One atomic transaction, including on recovery from an interrupted start.
    script = "${pkgs.nftables}/bin/nft -f ${ingressRules}";
    preStop = "${pkgs.nftables}/bin/nft delete table inet executor_otlp";
  };
  systemd.services.opentelemetry-collector = {
    requires = [ "executor-otlp-ingress.service" ];
    after = [ "executor-otlp-ingress.service" ];
  };
}
