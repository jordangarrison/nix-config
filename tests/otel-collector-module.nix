{ flake }:
let
  inherit (flake.inputs.nixpkgs) lib;
  cfg = flake.nixosConfigurations.endeavour.config;
  collector = cfg.services.opentelemetry-collector;
  settings = collector.settings;
  unit = cfg.systemd.services.opentelemetry-collector;
  results = {
    enabled = collector.enable && collector.package.pname == "otelcol-contrib";
    localExport = settings.exporters."otlphttp/maple".endpoint == "http://127.0.0.1:4318";
    noStoreSecret = settings.exporters."otlphttp/maple".headers."x-maple-ingest-key" == "\${env:MAPLE_INGEST_KEY}";
    runtimeCredential = unit.serviceConfig.LoadCredential == [ "ingest-key:/var/lib/maple-secrets/ingest-key" ];
    buildValidation = collector.validateConfigFile && collector.validateConfigOverrides != [ ];
    ordering = lib.elem "maple.service" unit.after && lib.elem "maple-secrets.service" unit.requires;
    journalAccess = lib.elem "systemd-journal" unit.serviceConfig.SupplementaryGroups;
    noTlsKeyAccess = !(lib.elem "nginx" unit.serviceConfig.SupplementaryGroups);
    logAccess = lib.elem "otel-logs" unit.serviceConfig.SupplementaryGroups
      && lib.any (lib.hasInfix "d:g:otel-logs:r-x") cfg.systemd.tmpfiles.rules;
    metrics = lib.attrNames settings.receivers.hostmetrics.scrapers == [ "cpu" "disk" "filesystem" "load" "memory" "network" "processes" ];
    bothFilesystems = settings.receivers.hostmetrics.scrapers.filesystem.include_mount_points.mount_points == [ "/" "/mnt/gemini" ];
    noDebug = settings.receivers.journald.priority == "info";
    noFeedback = lib.hasInfix "maple.service" (builtins.head settings.receivers.journald.operators).expr
      && lib.hasInfix "opentelemetry-collector.service" (builtins.head settings.receivers.journald.operators).expr;
    journalCursor = settings.receivers.journald.storage == "file_storage" && settings.receivers.journald.start_at == "end";
    logCursors = lib.all (r: r.storage == "file_storage" && r.start_at == "end") [
      settings.receivers."filelog/nginx-access" settings.receivers."filelog/nginx-error"
    ];
    boundedMemory = unit.serviceConfig.MemoryMax == "512M" && settings.processors.memory_limiter.limit_mib == 384;
    firstProcessor = lib.all (pipeline: builtins.head pipeline.processors == "memory_limiter") (lib.attrValues settings.service.pipelines);
    servicesPerSource = lib.all (name: settings.processors.${name}.attributes != [ ]) [
      "resource/host" "resource/journal" "resource/nginx-access" "resource/nginx-error"
    ];
    rotatedLogs = lib.elem "/var/log/nginx/*.log" cfg.services.logrotate.settings.nginx.files;
    noQueryStringInAccessLog = !(lib.hasInfix "$request_uri" cfg.services.nginx.commonHttpConfig)
      && lib.hasInfix ''"path":"$uri"'' cfg.services.nginx.commonHttpConfig;
    otherHostsUnchanged = lib.all (host: !flake.nixosConfigurations.${host}.config.services.opentelemetry-collector.enable) [
      "opportunity" "discovery" "voyager" "voyager-installer"
    ];
  };
in
assert lib.assertMsg (lib.all (x: x) (lib.attrValues results))
  "Collector module checks failed: ${lib.concatStringsSep ", " (lib.attrNames (lib.filterAttrs (_: result: !result) results))}";
results
