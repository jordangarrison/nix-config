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
    tracingModule = lib.any (module: module.pname == "otel") cfg.services.nginx.additionalModules;
    loopbackTraceReceiver = settings.receivers.otlp.protocols.grpc.endpoint == "127.0.0.1:4317"
      && !(lib.elem 4317 cfg.networking.firewall.allowedTCPPorts);
    modestSampling = lib.hasInfix "1% on;" cfg.services.nginx.commonHttpConfig
      && lib.hasInfix "otel_trace_context inject;" cfg.services.nginx.commonHttpConfig;
    noNginxDependency = !(lib.elem "opentelemetry-collector.service" cfg.systemd.services.nginx.requires)
      && !(lib.elem "opentelemetry-collector.service" cfg.systemd.services.nginx.after);
    traceSanitizer = lib.elem "transform/nginx" settings.service.pipelines.traces.processors;
    executorReceiver = settings.receivers."otlp/executor".protocols.http.endpoint == "172.17.0.1:4319"
      && !(settings.receivers."otlp/executor".protocols ? grpc);
    executorSignals = lib.all (signal:
      let pipeline = settings.service.pipelines."${signal}/executor";
      in pipeline.receivers == [ "otlp/executor" ]
        && pipeline.processors == [ "memory_limiter" "resource/executor" "batch" ]
        && pipeline.exporters == [ "otlphttp/maple" ]
    ) [ "traces" "logs" "metrics" ];
    executorIdentity = lib.elem { key = "deployment.environment.name"; value = "homelab"; action = "upsert"; }
      settings.processors."resource/executor".attributes
      && !(lib.any (attribute: attribute.key == "service.name") settings.processors."resource/executor".attributes);
    executorEnvironment = let container = cfg.virtualisation.oci-containers.containers.executor;
      in container.environment.OTEL_EXPORTER_OTLP_ENDPOINT == "http://172.17.0.1:4319"
        && container.environment.EXECUTOR_ENVIRONMENT == "homelab"
        && lib.hasSuffix ":${container.environment.EXECUTOR_BUILD_VERSION}" container.image
        && !(container.environment ? OTEL_EXPORTER_OTLP_HEADERS)
        && !(container.environment ? OTEL_EXPORTER_OTLP_METRICS_PROTOCOL);
    executorIngressGuard = lib.elem "executor-otlp-ingress.service" unit.requires
      && lib.elem "executor-otlp-ingress.service" unit.after
      && lib.elem "docker.service" cfg.systemd.services.executor-otlp-ingress.after
      && lib.hasInfix "/bin/nft -f" cfg.systemd.services.executor-otlp-ingress.script
      && lib.hasInfix "delete table inet executor_otlp" cfg.systemd.services.executor-otlp-ingress.preStop;
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
