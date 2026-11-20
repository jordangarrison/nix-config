{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "otel-collector-maple";
  nodes.machine = { lib, pkgs, ... }: {
    imports = [ ../modules/nixos/otel-collector.nix ../modules/nixos/nginx-tracing.nix ../modules/nixos/executor-telemetry.nix ];
    virtualisation.docker.enable = true;
    # Match endeavour: the dedicated ingress guard must work without the
    # general NixOS firewall, including when another interface can route here.
    networking.firewall.enable = false;
    networking.hostName = "endeavour";
    time.timeZone = "America/Chicago";
    virtualisation.memorySize = 2048;
    fileSystems."/mnt/gemini" = { device = "tmpfs"; fsType = "tmpfs"; };
    services.nginx = {
      enable = true;
      virtualHosts.localhost.locations = {
        "/".return = "200 otel-ok";
        # Deterministic span fixture; production sampling is asserted separately.
        "/trace-fixture" = {
          return = "200 otel-trace-ok";
          extraConfig = ''
            otel_trace on;
            add_header X-Trace-Id $otel_trace_id always;
          '';
        };
      };
    };
    # Only synthetic telemetry and a public test credential enter this VM.
    systemd.services.maple-secrets = {
      before = [ "maple.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; StateDirectory = "maple-secrets"; StateDirectoryMode = "0700"; UMask = "0077"; };
      script = ''printf '%s\n' integration-placeholder > /var/lib/maple-secrets/ingest-key'';
    };
    systemd.services.maple = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "maple-secrets.service" ];
      after = [ "maple-secrets.service" ];
      serviceConfig = {
        StateDirectory = "mock-maple";
        ExecStart = "${pkgs.python3}/bin/python3 ${pkgs.writeText "mock-maple.py" ''
          import gzip, json
          from http.server import BaseHTTPRequestHandler, HTTPServer
          class Handler(BaseHTTPRequestHandler):
              def log_message(self, *args):
                  pass
              def do_POST(self):
                  if self.headers.get("x-maple-ingest-key") != "integration-placeholder":
                      self.send_error(401)
                      return
                  body = self.rfile.read(int(self.headers["Content-Length"]))
                  if self.headers.get("Content-Encoding") == "gzip":
                      body = gzip.decompress(body)
                  with open("/var/lib/mock-maple/captured.jsonl", "a") as output:
                      output.write(json.dumps({"path": self.path, "data": json.loads(body)}) + "\n")
                  self.send_response(200)
                  self.send_header("Content-Type", "application/json")
                  self.end_headers()
                  self.wfile.write(b"{}")
          HTTPServer(("127.0.0.1", 4318), Handler).serve_forever()
        ''}";
      };
    };
    services.opentelemetry-collector.settings = {
      exporters."otlphttp/maple".encoding = "json";
      receivers.hostmetrics.collection_interval = lib.mkForce "2s";
      processors.batch.timeout = lib.mkForce "1s";
    };
    systemd.services.otel-journal-marker = {
      serviceConfig.Type = "oneshot";
      script = "echo otel-journal-accepted";
    };
    systemd.services.otel-journal-after-restart = {
      serviceConfig.Type = "oneshot";
      script = "echo otel-journal-after-restart";
    };
    systemd.services.blocky = {
      serviceConfig.Type = "oneshot";
      script = ''
        echo blocky-info-dropped
        echo '<4>blocky-warning-kept'
      '';
    };
    environment.systemPackages = [ pkgs.curl pkgs.acl pkgs.iproute2 pkgs.nftables pkgs.iptables ];
  };
  testScript = ''
    import json, shlex, time
    machine.start()
    machine.wait_for_unit("maple.service")
    machine.wait_for_unit("opentelemetry-collector.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_until_succeeds("test -s /var/lib/mock-maple/captured.jsonl")
    machine.wait_until_succeeds("journalctl -u opentelemetry-collector --grep 'Everything is ready'")

    # Emulate a container on the real Docker bridge without pulling an image.
    machine.succeed("ip netns add otlp-client; ip link add otlp-host type veth peer name eth0 netns otlp-client; ip link set otlp-host master docker0; ip link set otlp-host up; ip -n otlp-client addr add 172.17.0.2/16 dev eth0; ip -n otlp-client link set eth0 up")
    now = str(time.time_ns())
    resource = {"attributes": [{"key": "service.name", "value": {"stringValue": "executor-test"}}]}
    fixtures = {
        "traces": {"resourceSpans": [{"resource": resource, "scopeSpans": [{"spans": [{"traceId": "1234567890abcdef1234567890abcdef", "spanId": "1234567890abcdef", "name": "executor-test-span", "startTimeUnixNano": now, "endTimeUnixNano": now}]}]}]},
        "logs": {"resourceLogs": [{"resource": resource, "scopeLogs": [{"logRecords": [{"timeUnixNano": now, "body": {"stringValue": "executor-test-log"}}]}]}]},
        "metrics": {"resourceMetrics": [{"resource": resource, "scopeMetrics": [{"metrics": [{"name": "executor.test", "gauge": {"dataPoints": [{"timeUnixNano": now, "asDouble": 1}]}}]}]}]},
    }
    for signal, payload in fixtures.items():
        machine.succeed("ip netns exec otlp-client curl -fsS -H 'Content-Type: application/json' --data " + shlex.quote(json.dumps(payload)) + " http://172.17.0.1:4319/v1/" + signal)
    # The default metrics protocol needs no http/json override.
    machine.succeed("ip netns exec otlp-client curl -fsS -H 'Content-Type: application/x-protobuf' --data-binary @/dev/null http://172.17.0.1:4319/v1/metrics")
    machine.wait_until_succeeds("grep -q executor-test-span /var/lib/mock-maple/captured.jsonl && grep -q executor-test-log /var/lib/mock-maple/captured.jsonl && grep -q executor.test /var/lib/mock-maple/captured.jsonl")
    # Host-local and off-bridge clients cannot use the unauthenticated receiver.
    machine.fail("curl -fsS --max-time 2 http://172.17.0.1:4319/v1/traces")
    machine.succeed("ip netns add otlp-denied; ip link add otlp-outside type veth peer name eth0 netns otlp-denied; ip addr add 192.0.2.1/24 dev otlp-outside; ip link set otlp-outside up; ip -n otlp-denied addr add 192.0.2.2/24 dev eth0; ip -n otlp-denied link set eth0 up; ip -n otlp-denied route add default via 192.0.2.1")
    machine.fail("ip netns exec otlp-denied curl -fsS --max-time 2 http://172.17.0.1:4319/v1/traces")
    machine.succeed("nft list chain inet executor_otlp ingest | grep -E 'counter packets [2-9][0-9]* bytes .* reject'")
    # An ACCEPT inserted by another service must not bypass this guard.
    machine.succeed("iptables -I INPUT -j ACCEPT")
    machine.fail("ip netns exec otlp-denied curl -fsS --max-time 2 http://172.17.0.1:4319/v1/traces")
    machine.succeed("iptables -D INPUT -j ACCEPT")

    # Check ACL inheritance on initial creation, rename rotation, and reopen.
    machine.succeed("curl -fsS 'http://127.0.0.1/first?not_logged=private-query'")
    machine.wait_until_succeeds("grep -q /first /var/lib/mock-maple/captured.jsonl")
    machine.succeed("mv /var/log/nginx/access.log /var/log/nginx/access.log.1; systemctl kill --signal=USR1 --kill-whom=main nginx")
    machine.wait_until_succeeds("test -f /var/log/nginx/access.log")
    machine.succeed("curl -fsS http://127.0.0.1/after-rotation")
    machine.wait_until_succeeds("grep -q /after-rotation /var/lib/mock-maple/captured.jsonl")
    machine.fail("grep -q private-query /var/lib/mock-maple/captured.jsonl")
    machine.succeed("getfacl /var/log/nginx/access.log | grep -q 'group:otel-logs:r-x'")

    # Synthetic error line uses the declared nginx format and local timezone.
    machine.succeed("echo '2026/11/20 03:00:00 [error] 123#123: otel-error-marker' >> /var/log/nginx/error.log")
    machine.wait_until_succeeds("grep -q otel-error-marker /var/lib/mock-maple/captured.jsonl")
    machine.succeed("systemctl start otel-journal-marker")
    machine.wait_until_succeeds("grep -q otel-journal-accepted /var/lib/mock-maple/captured.jsonl")
    machine.succeed("systemctl start blocky")
    machine.wait_until_succeeds("grep -q blocky-warning-kept /var/lib/mock-maple/captured.jsonl")
    machine.fail("grep -q blocky-info-dropped /var/lib/mock-maple/captured.jsonl")
    machine.wait_until_succeeds("grep -q system.cpu.time /var/lib/mock-maple/captured.jsonl")
    machine.wait_until_succeeds("grep -q system.filesystem.usage /var/lib/mock-maple/captured.jsonl")

    # Actual dynamic module -> OTLP/gRPC -> collector -> OTLP/HTTP span export.
    headers = machine.succeed("curl -fsSD - -o /dev/null -H 'traceparent: 00-11111111111111111111111111111111-2222222222222222-01' 'http://127.0.0.1/trace-fixture?not_logged=private-query'")
    trace_id = next(line.split(': ', 1)[1].strip() for line in headers.splitlines() if line.lower().startswith('x-trace-id:'))
    assert trace_id != '11111111111111111111111111111111', headers
    machine.wait_until_succeeds("grep -q " + trace_id + " /var/lib/mock-maple/captured.jsonl")
    machine.fail("grep -q private-query /var/lib/mock-maple/captured.jsonl")

    # nginx must keep serving when telemetry is unavailable.
    machine.succeed("systemctl stop opentelemetry-collector")
    machine.succeed("curl -fsS http://127.0.0.1/trace-fixture")
    # A collector restart must retain cursors instead of replaying old records.
    machine.succeed("systemctl start opentelemetry-collector")
    machine.wait_until_succeeds("journalctl -u opentelemetry-collector --grep 'Everything is ready' | test $(wc -l) -ge 2")
    machine.succeed("systemctl start otel-journal-after-restart")
    machine.succeed("curl -fsS http://127.0.0.1/after-restart")
    machine.wait_until_succeeds("grep -q /after-restart /var/lib/mock-maple/captured.jsonl")
    machine.wait_until_succeeds("grep -q otel-journal-after-restart /var/lib/mock-maple/captured.jsonl")
    captured = [json.loads(line) for line in machine.succeed("cat /var/lib/mock-maple/captured.jsonl").splitlines()]
    logs = [record for batch in captured for resource in batch["data"].get("resourceLogs", []) for scope in resource["scopeLogs"] for record in scope["logRecords"]]
    bodies = [record.get("body", {}).get("stringValue", "") for record in logs]
    assert bodies.count("otel-journal-accepted") == 1, bodies
    assert sum('/first' in body for body in bodies) == 1, bodies
    spans = [span for batch in captured for resource in batch["data"].get("resourceSpans", []) for scope in resource["scopeSpans"] for span in scope["spans"]]
    assert any(span["traceId"] == trace_id for span in spans), spans
    for span in spans:
        attrs = {attr["key"]: attr["value"] for attr in span.get("attributes", [])}
        assert not any(key in attrs for key in ["http.user_agent", "net.sock.peer.addr", "net.sock.peer.port"]), attrs
        if "http.target" in attrs:
            assert '?' not in attrs["http.target"]["stringValue"], attrs
    for batch in captured:
        for resource in batch["data"].get("resourceMetrics", []) + batch["data"].get("resourceLogs", []) + batch["data"].get("resourceSpans", []):
            attrs = {attr["key"]: attr["value"].get("stringValue") for attr in resource["resource"]["attributes"]}
            assert attrs["host.name"] == "endeavour", attrs
            assert attrs["service.name"] in ["hostmetrics", "system-journal", "nginx-access", "nginx-error", "nginx", "executor-test"], attrs
            if attrs["service.name"] == "executor-test":
                assert attrs["service.namespace"] == "executor", attrs
                assert attrs["deployment.environment.name"] == "homelab", attrs
    machine.fail("journalctl -u opentelemetry-collector --grep 'permission denied|failed to process|failed to export' --case-sensitive=no")
    # Removing the guard must first stop the receiver. Starting the collector
    # recreates its required guard; no broad firewall flush is involved.
    machine.succeed("systemctl stop executor-otlp-ingress")
    machine.fail("systemctl is-active opentelemetry-collector")
    machine.fail("nft list table inet executor_otlp")
    machine.succeed("systemctl start opentelemetry-collector")
    machine.wait_for_unit("executor-otlp-ingress.service")
    machine.wait_for_unit("opentelemetry-collector.service")
    machine.wait_until_succeeds("ip netns exec otlp-client curl -fsS -H 'Content-Type: application/x-protobuf' --data-binary @/dev/null http://172.17.0.1:4319/v1/metrics")
  '';
}
