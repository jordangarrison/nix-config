{ config, pkgs, ... }:

{
  # Keep tracing separate from log collection so it can be reverted alone.
  # nixpkgs builds this dynamic module with the SAME nginx sources and ABI.
  services.nginx = {
    additionalModules = [ pkgs.nginxModules.otel ];
    commonHttpConfig = ''
      otel_exporter {
        endpoint 127.0.0.1:4317;
        interval 5s;
        batch_size 128;
        batch_count 2;
      }
      otel_service_name nginx;
      split_clients "$otel_trace_id" $maple_trace_sample {
        1% on;
        * off;
      }
      otel_trace $maple_trace_sample;
      # Start a fresh context: incoming sampled flags cannot force full-volume tracing.
      otel_trace_context inject;
    '';
  };

  services.opentelemetry-collector.settings = {
    receivers.otlp.protocols.grpc.endpoint = "127.0.0.1:4317";
    processors = {
      "resource/nginx-traces".attributes = [
        { key = "host.name"; value = config.networking.hostName; action = "upsert"; }
        { key = "service.name"; value = "nginx"; action = "upsert"; }
      ];
      # nginx's built-in span attributes include the full request target. Do not
      # retain query tokens or client identifiers just because a request was sampled.
      "transform/nginx" = {
        error_mode = "propagate";
        trace_statements = [{
          context = "span";
          statements = [
            ''replace_pattern(attributes["http.target"], "\\?.*$", "") where attributes["http.target"] != nil''
            ''delete_key(attributes, "http.user_agent")''
            ''delete_key(attributes, "net.sock.peer.addr")''
            ''delete_key(attributes, "net.sock.peer.port")''
          ];
        }];
      };
    };
    service.pipelines.traces = {
      receivers = [ "otlp" ];
      processors = [ "memory_limiter" "resource/nginx-traces" "transform/nginx" "batch" ];
      exporters = [ "otlphttp/maple" ];
    };
  };
  # No nginx dependency on the collector and no firewall port. If the collector
  # is down, nginx keeps serving; its bounded export buffer drops excess spans.
}
