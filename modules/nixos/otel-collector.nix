{ config, lib, pkgs, ... }:

let
  cfg = config.services.opentelemetry-collector;
  state = "/var/lib/opentelemetry-collector";
  resource = name: {
    attributes = [
      { key = "host.name"; value = config.networking.hostName; action = "upsert"; }
      { key = "service.name"; value = name; action = "upsert"; }
    ];
  };
  start = pkgs.writeShellScript "otel-collector-start" ''
    set -euo pipefail
    # Read only at runtime. Neither the key nor an expanded config enters the store.
    export MAPLE_INGEST_KEY="$(< "$CREDENTIALS_DIRECTORY/ingest-key")"
    exec ${lib.getExe cfg.package} --config=file:${config.system.build.opentelemetryCollectorConfig}
  '';
in
{
  services.opentelemetry-collector = {
    enable = true;
    package = pkgs.opentelemetry-collector-contrib;
    # Validation must not read the real credential (or require it at build time).
    validateConfigOverrides = [ "exporters::otlphttp/maple::headers::x-maple-ingest-key=validation-only" ];
    settings = {
      extensions.file_storage = {
        directory = state;
        create_directory = true;
        compaction = { on_start = true; directory = "${state}/compaction"; };
      };
      receivers = {
        hostmetrics = {
          collection_interval = "60s";
          scrapers = {
            cpu = { };
            memory = { };
            load = { };
            disk = { };
            filesystem = {
              include_mount_points = {
                mount_points = [ "/" "/mnt/gemini" ];
                match_type = "strict";
              };
            };
            network = { };
            # Counts by process state, not per-process command lines or arguments.
            processes = { };
          };
        };
        journald = {
          journalctl_path = "${pkgs.systemd}/bin/journalctl";
          start_at = "end";
          priority = "info"; # emergency through info; no debug
          storage = "file_storage";
          retry_on_failure.enabled = true;
          operators = [
            {
              type = "filter";
              # Avoid ingest/export feedback loops and duplicate nginx error logs.
              # Blocky's successful DNS-query logs dominate the journal; retain warnings/errors.
              expr = ''body["_SYSTEMD_UNIT"] in ["opentelemetry-collector.service", "maple.service", "nginx.service"] or (body["_SYSTEMD_UNIT"] == "blocky.service" and body["PRIORITY"] == "6")'';
            }
            { type = "move"; from = "body"; to = "attributes.journald"; }
            { type = "move"; from = "attributes.journald.MESSAGE"; to = "body"; }
            {
              type = "severity_parser";
              parse_from = "attributes.journald.PRIORITY";
              mapping = {
                fatal = [ "0" "1" "2" ];
                error = "3";
                warn = "4";
                info = [ "5" "6" ];
                debug = "7";
              };
            }
          ];
        };
        "filelog/nginx-access" = {
          include = [ "/var/log/nginx/access.log" ];
          start_at = "end";
          storage = "file_storage";
          include_file_path = true;
          retry_on_failure.enabled = true;
          operators = [{
            type = "json_parser";
            timestamp = { parse_from = "attributes.time"; layout_type = "gotime"; layout = "2006-01-02T15:04:05Z07:00"; };
          }];
        };
        "filelog/nginx-error" = {
          include = [ "/var/log/nginx/error.log" ];
          start_at = "end";
          storage = "file_storage";
          include_file_path = true;
          retry_on_failure.enabled = true;
          operators = [{
            type = "regex_parser";
            regex = ''^(?P<time>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(?P<severity>\w+)\] (?P<pid>\d+)#(?P<tid>\d+): (?P<message>.*)$'';
            timestamp = { parse_from = "attributes.time"; layout = "%Y/%m/%d %H:%M:%S"; location = config.time.timeZone; };
            severity = { parse_from = "attributes.severity"; };
          }];
        };
      };
      processors = {
        memory_limiter = { check_interval = "1s"; limit_mib = 384; spike_limit_mib = 96; };
        batch = { timeout = "5s"; send_batch_size = 512; send_batch_max_size = 1024; };
        "resource/host" = resource "hostmetrics";
        "resource/journal" = resource "system-journal";
        "resource/nginx-access" = resource "nginx-access";
        "resource/nginx-error" = resource "nginx-error";
      };
      exporters."otlphttp/maple" = {
        endpoint = "http://127.0.0.1:4318";
        headers."x-maple-ingest-key" = "\${env:MAPLE_INGEST_KEY}";
        compression = "gzip";
        timeout = "15s";
        sending_queue = { enabled = true; queue_size = 128; num_consumers = 2; };
        retry_on_failure = { enabled = true; initial_interval = "5s"; max_interval = "30s"; max_elapsed_time = "300s"; };
      };
      service = {
        extensions = [ "file_storage" ];
        # No collector telemetry listener on a wildcard address.
        telemetry.metrics.level = "none";
        pipelines = {
          metrics = { receivers = [ "hostmetrics" ]; processors = [ "memory_limiter" "resource/host" "batch" ]; exporters = [ "otlphttp/maple" ]; };
          "logs/journal" = { receivers = [ "journald" ]; processors = [ "memory_limiter" "resource/journal" "batch" ]; exporters = [ "otlphttp/maple" ]; };
          "logs/nginx-access" = { receivers = [ "filelog/nginx-access" ]; processors = [ "memory_limiter" "resource/nginx-access" "batch" ]; exporters = [ "otlphttp/maple" ]; };
          "logs/nginx-error" = { receivers = [ "filelog/nginx-error" ]; processors = [ "memory_limiter" "resource/nginx-error" "batch" ]; exporters = [ "otlphttp/maple" ]; };
        };
      };
    };
  };

  systemd.services.opentelemetry-collector = {
    wants = [ "maple.service" ];
    requires = [ "maple-secrets.service" ];
    after = [ "maple.service" "maple-secrets.service" ];
    environment.GOMEMLIMIT = "320MiB";
    serviceConfig = {
      ExecStart = lib.mkForce start;
      LoadCredential = [ "ingest-key:/var/lib/maple-secrets/ingest-key" ];
      SupplementaryGroups = [ "otel-logs" ]; # systemd-journal is supplied by nixpkgs
      MemoryMax = "512M";
      UMask = "0077";
    };
  };

  # Log read access only: joining nginx's group would also grant access to TLS keys.
  users.groups.otel-logs = { };
  systemd.tmpfiles.rules = [
    "d /var/log/nginx 0750 nginx nginx - -"
    "a+ /var/log/nginx - - - - g:otel-logs:r-x,d:g:otel-logs:r-x"
    "a+ /var/log/nginx/*.log - - - - g:otel-logs:r--"
  ];
  services.nginx = {
    # nixpkgs defaults: access log under the nginx prefix (/var/spool/nginx),
    # errors to stderr. Declare stable, rotated paths for filelog instead.
    logError = "/var/log/nginx/error.log warn";
    commonHttpConfig = ''
      log_format otel_json escape=json '{"time":"$time_iso8601","host":"$host",'
        '"method":"$request_method","path":"$uri","status":$status,'
        '"bytes_sent":$bytes_sent,"request_time":$request_time}';
      access_log /var/log/nginx/access.log otel_json;
    '';
  };
  # nixpkgs already rotates /var/log/nginx/*.log and reopens nginx's descriptors.
}
