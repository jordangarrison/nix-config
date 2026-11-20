# Maple on endeavour

Maple Local serves its bundled dashboard, query API and OTLP/HTTP ingest at
`https://maple.jordangarrison.dev` through the tailnet-only nginx vhost.
The backend listens only on `127.0.0.1:4318`; no direct ingest port is opened.
The Cloudflare A record points at `100.118.65.11` (unproxied, TTL 1).

The input is tagged **v0.3.6**, but that tag's `nix/release.json` packages the
**v0.3.5 binary**. This is upstream's pinned release bundle, not a source build.
Update the input and inspect its release manifest together when upgrading.

## Authentication

The first service start generates two separate 256-bit random hex credentials
under `/var/lib/maple-secrets` (root-only directory, files mode `0600`).
Existing credentials are retained. Malformed files cause startup to fail rather
than silently rotating them. systemd credentials deliver them to Maple outside
the Nix store. Never paste these values in a PR, terminal recording, or log.

Jordan can read them privately on endeavour:

```sh
sudo cat /var/lib/maple-secrets/access-token
sudo cat /var/lib/maple-secrets/ingest-key
```

- **Dashboard:** enter the access token at `/login`. Maple issues a 30-day
  session cookie. The query API also accepts `Authorization: Bearer <access-token>`.
- **Exporters:** use OTLP **HTTP/protobuf**, not gRPC. Set
  `OTEL_EXPORTER_OTLP_ENDPOINT=https://maple.jordangarrison.dev` and
  `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`. Supply
  `x-maple-ingest-key=<ingest-key>` through your exporter's secret mechanism
  (`OTEL_EXPORTER_OTLP_HEADERS` for SDKs that support it).
  `Authorization: Bearer <ingest-key>` is also accepted. The signal paths are
  `/v1/traces`, `/v1/logs`, and `/v1/metrics`. Signal-specific endpoint settings
  must include those paths. An ingest key grants writes, not dashboard reads.

To rotate a credential, replace its root-only file privately and restart Maple
only after approval. Rotating the access token also invalidates browser cookies.
The proxy forwards the original Host and HTTPS scheme for same-origin checks
and secure cookies. Do not add nginx basic auth in front of the ingest paths.

## Storage and retention

The dedicated 250 GB Samsung 860 EVO drive (Gemini) has an ext4 filesystem:

- UUID: `daefadb8-2bb3-4073-8fb8-d4820021506a`
- Mount: `/mnt/gemini` (about 233 GiB before filesystem overhead)
- State: `/mnt/gemini/maple`, bind-mounted at `/var/lib/maple`

The owner's approved disk preparation created the GPT partition and ext4
filesystem. Nix does **not** format it. The configuration mounts it only when
applied. No loopback volume or root-filesystem telemetry store is used.
`nofail` plus a five-second device timeout lets the host boot without Gemini.
Maple requires the bind mount, which requires Gemini; a failed mount blocks
Maple rather than creating a fallback store on `/`. The state-directory unit
checks that Gemini is mounted before creating its private directory.

All Maple state, including embedded ClickHouse, checkpoint copies and store
sidecars, is on Gemini. Root retains the package in the Nix store, small
credential files and normal system journal entries. Nothing exports telemetry
to Maple by default. For the expected low-volume homelab/agent workload, the
initial planning estimate is 5–30 GB, **not a measured limit**; checkpoints and
rollups can add more. No size cap is configured on the dedicated drive.

Keep the bundled schema TTLs: raw traces/logs expire after **30 days**, raw
metrics after **90 days**; derived tables have their own, sometimes longer,
TTLs. Expiry occurs during ClickHouse merges, not immediately at the age
boundary. `--minimum-raw-telemetry-retention-days` only **lengthens** retention
(minimum 90 days); it cannot implement a short retention policy.

Check usage after deployment:

```sh
sudo du -sh /mnt/gemini/maple
df -h /mnt/gemini
systemctl status maple var-lib-maple.mount mnt-gemini.mount
journalctl -u maple --since today
```

Revisit storage/ingest volume if state passes **150 GB**. If the drive fills,
ingest and checkpoint writes can fail; there is no automatic deletion on
ENOSPC. Reduce telemetry at the exporters or plan a data migration before that.
Do not delete ClickHouse files while Maple runs.

## Recovery and migration

Checkpoints refresh every 30 minutes. After an unclean stop Maple deliberately
fails closed (`onDirtyStore = "fail"`) instead of automatically wiping or
rolling back telemetry. Inspect the journal and available checkpoints before
choosing a recovery action. A restore loses live data since that checkpoint;
never reset or restore automatically just to clear an ENOSPC failure.
Upstream operations can run as the service user with its HOME, for example:

```sh
sudo -u maple env HOME=/var/lib/maple maple schema status
```

Stop/restart, restore, filesystem growth and migration require approval.
Before changing storage, stop Maple cleanly, back up its full state and preserve
ownership. The storage provider is selected by one import in
`modules/nixos/maple.nix`; `modules/nixos/maple/gemini-storage.nix` owns the source
path and mount ordering. Point a replacement provider at a prepared filesystem,
copy state while stopped, then validate the mount dependencies before applying.
Do not remove Gemini's mount while leaving a writable fallback path on `/`.
Removing Maple's Nix configuration does not erase its data or credentials.
