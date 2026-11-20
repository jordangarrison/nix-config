# Endeavour telemetry collector

`modules/nixos/otel-collector.nix` sends host metrics and system/nginx logs to
Maple over **loopback OTLP/HTTP**. It also relays the personal self-hosted
Executor's OTLP signals from Docker. Datadog and the Claude Code/Codex telemetry
settings are unchanged. This collector is not an agent-telemetry proxy.

## Sources

| Source | Maple `service.name` | Content |
| --- | --- | --- |
| `hostmetrics`, every 60 seconds | `hostmetrics` | CPU, memory, load, disk I/O, filesystem usage for `/` and `/mnt/gemini`, network I/O, process-state counts. No per-process arguments. |
| `journald` | `system-journal` | System journal, emergency through info. Unit and other journal fields are in `journald` attributes; message is the body. No debug, Blocky info-level DNS query noise, collector/Maple feedback, or duplicate nginx journal records. |
| `filelog/nginx-access` | `nginx-access` | `/var/log/nginx/access.log`, JSON: timestamp, host, method, path **without query string**, status, bytes, request duration. No client IP, authorization, cookies, referrer, or user-agent. |
| `filelog/nginx-error` | `nginx-error` | `/var/log/nginx/error.log`, nginx text format, warn and above, with parsed time/severity. |
| nginx `ngx_otel_module` | `nginx` | Request spans at 1% sampling, via loopback OTLP/gRPC to the collector. Query strings, user agents, and client socket addresses/ports are removed before export. |
| Executor OTLP/HTTP | Preserved from Executor | Application traces, logs, and metrics. All carry `service.namespace=executor`, `deployment.environment.name=homelab`, and `host.name=endeavour`. |

nginx's defaults use its prefix for access logs and stderr for errors. This
module declares both paths explicitly. nixpkgs' existing logrotate rule rotates
`/var/log/nginx/*.log` weekly and reopens nginx descriptors. The collector gets
read-only access through an `otel-logs` ACL, including inherited access after
rotation, **not** nginx group membership (which would expose TLS private keys).

Journal messages and nginx errors can still contain private application data or
URLs. Access-log paths can contain private path segments. Treat Maple's contents
as private; do not paste live records into public issues, tests, or PRs. These
source filters are not a general secret scrubber.

## Credentials, state, and failure behavior

- `maple-secrets.service` creates the existing root-only ingest key.
- `LoadCredential` passes it to the collector. A small startup wrapper reads the
  credential into `MAPLE_INGEST_KEY`; only an environment reference is in the
  store config. Build-time validation uses a public placeholder override.
- The exporter connects directly to `http://127.0.0.1:4318`, with
  `x-maple-ingest-key`; no nginx hop. Executor's separate bridge ingress is
  guarded as described below.
- The collector starts after Maple, but does not require a working Maple
  process: it can reconnect after Maple recovers. It requires the credential
  provisioner. It never starts nginx or makes nginx depend on telemetry.
- `/var/lib/opentelemetry-collector` holds **cursors**, not a telemetry archive.
  Journal and file receivers start at the end on first use and resume from
  persisted cursors after restart. There is no historical backfill.
- A memory limiter, 320 MiB Go soft limit, 512 MiB systemd hard limit, bounded
  in-memory export queue, and five-minute export retry window bound resource
  use. Outages can lose data after retries/queue exhaustion; the queue is not
  durable across restart. Cursor storage is not an exactly-once guarantee.
- Collector self-metrics are disabled. This avoids another listener and a
  self-observation loop. Check its unit journal for exporter failures.

## Executor: Docker → collector → Maple

`modules/nixos/executor-telemetry.nix`, imported by `executor.nix`, owns this
path. The container sends to `http://172.17.0.1:4319` on Docker's default
`docker0` bridge (`172.17.0.0/16`). Port 4318 remains Maple's loopback-only
listener; nginx's trace receiver remains loopback-only port 4317. No wildcard
listener, published Docker port, or Maple key is added to the container.
If Docker's default bridge addressing changes, update this module with it.

Endeavour's general firewall is **disabled**, so `networking.firewall` allow
rules would not protect this listener. `executor-otlp-ingress.service` installs
an independent **nftables input hook** for `172.17.0.1:4319`: accept only packets
arriving on `docker0` from `172.17.0.0/16`, reject all other sources/interfaces,
including host-local callers. DOCKER-USER is not sufficient: it filters
forwarding, not packets addressed to the host. An iptables INPUT jump can also
be bypassed if another service inserts an ACCEPT rule ahead of it. The dedicated
`inet executor_otlp` table avoids that rule-order dependency without enabling
the general firewall; it is installed in one atomic transaction. The collector
requires this guard and starts after it; the guard starts after Docker creates
its bridge. Stop ordering closes the collector before removing the guard. Other
ports and the general firewall policy are unchanged. Any container on this
bridge can submit telemetry: this is a network boundary, not per-container
authentication.

The base `OTEL_EXPORTER_OTLP_ENDPOINT` enables **all three signals**; it is not
container loopback. Executor uses HTTP/JSON for traces/logs and HTTP/protobuf
for metrics. The collector accepts both and forwards protobuf to Maple, so no
metrics-protocol override is needed. `EXECUTOR_ENVIRONMENT=homelab` and
`EXECUTOR_BUILD_VERSION` tracks the image tag. Service names are not replaced,
so Executor's host/runtime/browser identities remain distinct. The host
collector adds the namespace and environment to each signal. Upstream service
names can change with the image; filter Maple by the namespace to find them.

This replaces the bundled collector as the destination. Its supervised process
can still run idle; old records are not deleted. Not every request creates a
log record: warnings/errors and app page requests do, while normal requests
may produce traces only. The journal can still contain the container's stdout,
so application logs may also appear under `system-journal`. No sampling or
application-data scrubber is added to Executor's OTLP pipeline. Treat those
records as private and recheck Gemini's disk growth after rollout.

After the approved deployment:

1. Confirm `docker-executor`, `executor-otlp-ingress`, and
   `opentelemetry-collector` are active. Inspect only the three declared
   telemetry env fields, never dump the container environment.
2. Make a request to `https://executor.jordangarrison.dev`, then inspect Maple
   traces/logs under namespace `executor` and environment `homelab`. Inspect
   metrics once Executor emits them; an empty log search alone is not failure.
3. Verify synthetic OTLP POSTs from the Docker bridge succeed and off-bridge
   attempts fail. `sudo nft list table inet executor_otlp` shows the guard's
   counters.
4. Compare all existing `*.jordangarrison.dev` vhost status codes before/after.

Revert the Executor environment/import and this module to return to its bundled
collector. Apply rollback through the normal guarded flow. Do not remove the
ingress guard while a bridge receiver is still listening.

## Volume and disk budget

A 24-hour sample on endeavour before rollout contained about **389,000 journal
records / 0.53 GB of journal JSON**. Blocky accounted for 284,000 records /
0.39 GB; dropping its info-level queries removes most of that traffic. The
remaining journal input is about **0.14 GB/day before OTLP encoding**. These are
measured input sizes, not measured Maple disk growth.

Budget **0.2–1 GB/day of total uncompressed ingest** initially for retained
journal records, host metrics, and modest nginx traffic. For nginx access logs,
100,000 requests/day adds roughly 0.03–0.1 GB/day; request rate and application
errors can change that greatly. Maple compression, derived tables, checkpoints,
and merges make disk growth differ from ingest bytes. No hard disk quota is set.

Maple retains raw logs/traces for 30 days and raw metrics for 90 days, plus
longer-lived derived tables. At inspection, Gemini had **117 GiB free**, not the
older 217 GiB estimate. Recheck after the first 24 hours and again after a week;
reduce sources/intervals before relying on a rough retention projection.

```sh
systemctl status opentelemetry-collector maple
journalctl -u opentelemetry-collector --since '1 hour ago'
sudo du -sh /mnt/gemini/maple /var/lib/opentelemetry-collector
df -h /mnt/gemini
```

## Rollout and verify

Build/check first. Deploy only with Jordan's approval, in **build → test → switch**
order, with `--no-nom` on every nh invocation. No credential copy or additional
secret is needed. Once applied:

1. Open <https://maple.jordangarrison.dev> and log in with the existing access
   token through its private credential flow (see [Maple](maple.md)).
2. Filter metrics by `host.name=endeavour`, `service.name=hostmetrics`; graph
   `system.cpu.time`, `system.memory.usage`, `system.filesystem.usage` and
   `system.network.io`. Filesystem attributes distinguish `/` and `/mnt/gemini`.
3. Filter logs by `system-journal`, `nginx-access`, and `nginx-error`. A normal
   site request should produce an access record. Confirm new records after the
   first log rotation and a collector restart.
4. Filter traces by `service.name=nginx`. About one in 100 requests is sampled;
   a quiet host may take a while to show a trace. These are nginx request spans,
   not automatic backend instrumentation. Backends must support W3C context to
   join the trace.
5. Check disk growth. Keep Datadog running independently.

Validation:

```sh
nix build --no-link .#checks.x86_64-linux.otel-collector-module
nix build --no-link .#checks.x86_64-linux.otel-collector-runtime
nix build --no-link .#nixosConfigurations.endeavour.config.system.build.opentelemetryCollectorConfig
nh os build . -H endeavour --no-nom
```

The config derivation runs `otelcol-contrib validate` without the live key. The
isolated VM test checks the actual credential wrapper/export header, journal
filters, host metrics, parsers, inherited log ACLs, log rotation, and persisted
cursors against a synthetic Maple HTTP sink. It also loads nginx's dynamic
module, exports a deterministic fixture span through gRPC and HTTP, checks
attribute removal, and confirms nginx serves when the collector stops. Docker
bridge fixtures exercise all three Executor signal pipelines, JSON/protobuf
acceptance, preserved service names, namespace/environment attribution, and
rejection of host-local/off-bridge ingress with the general firewall disabled.
It never reads the host's secrets.

## nginx tracing and rollback

`modules/nixos/nginx-tracing.nix` adds nixpkgs' **`nginxModules.otel`** (native
`ngx_otel_module`, not the older third-party OpenTelemetry webserver module).
nixpkgs builds the module and nginx against the same source/ABI and loads the
module dynamically. The standard nginx config build also checks its directives.

`split_clients` samples 1% by freshly generated trace ID. `otel_trace_context
inject` overwrites incoming context so a caller's sampled flag cannot force
100% tracing. This intentionally does not join incoming parent traces. Upstream
requests receive the new W3C context. The collector listens only on
`127.0.0.1:4317`, then adds the Maple credential on the HTTP hop; nginx never
receives the ingest key. Any local process can submit spans on this loopback
receiver; it is not an authenticated multi-user boundary.

nginx buffers at most two batches of 128 spans per worker and flushes every five
seconds. Excess spans can be dropped if telemetry is unavailable; nginx has no
unit dependency on Maple or the collector. Sampling limits volume, not all of
the module's per-request overhead. Check latency and resource use after rollout.

Tracing is a separate commit. Revert that commit to remove the module, gRPC
receiver, and trace pipeline while keeping host metrics and log collection.
Apply any rollback with the normal guarded deployment flow; changing nginx's
module package may restart nginx, not merely reload it.
