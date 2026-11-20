{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "otel-collector-maple";
  nodes.machine = { lib, pkgs, ... }: {
    imports = [ ../modules/nixos/otel-collector.nix ];
    networking.hostName = "endeavour";
    time.timeZone = "America/Chicago";
    virtualisation.memorySize = 2048;
    fileSystems."/mnt/gemini" = { device = "tmpfs"; fsType = "tmpfs"; };
    services.nginx = {
      enable = true;
      virtualHosts.localhost.locations."/".return = "200 otel-ok";
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
    environment.systemPackages = [ pkgs.curl pkgs.acl ];
  };
  testScript = ''
    import json
    machine.start()
    machine.wait_for_unit("maple.service")
    machine.wait_for_unit("opentelemetry-collector.service")
    machine.wait_for_unit("nginx.service")
    machine.wait_until_succeeds("test -s /var/lib/mock-maple/captured.jsonl")
    machine.wait_until_succeeds("journalctl -u opentelemetry-collector --grep 'Everything is ready'")

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

    # A collector restart must retain cursors instead of replaying old records.
    machine.succeed("systemctl restart opentelemetry-collector")
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
    for batch in captured:
        for resource in batch["data"].get("resourceMetrics", []) + batch["data"].get("resourceLogs", []):
            attrs = {attr["key"]: attr["value"].get("stringValue") for attr in resource["resource"]["attributes"]}
            assert attrs["host.name"] == "endeavour", attrs
            assert attrs["service.name"] in ["hostmetrics", "system-journal", "nginx-access", "nginx-error"], attrs
    machine.fail("journalctl -u opentelemetry-collector --grep 'permission denied|failed to process|failed to export' --case-sensitive=no")
  '';
}
