# Workspace additions: dev/kartingcoach

Read after `ROUTER.md` (this folder's `AGENTS.md`). This workspace is the
**Race Monitor** platform (race-monitor.com — live race/karting timing) plus
the older **Karting Coach / KartTuner** product.

## The big picture

```
trackside timing hardware / iRacing
        │  (RMonitor / IMSA Enhanced RMon protocol)
        ▼
kc-racemonitor-relay        desktop relay clients (Windows/.NET, macOS, AIR)
        ▼
kc-racemonitor-services     containerized relay/state/aggregation microservices on AKS
(kc-racemonitor-server)     ← legacy pre-container Node predecessor of the same tier
        ▼
kc-racemonitor-web          live timing display (ReactTiming) embedded as widget/iframe
kc-racemonitor-websites     .NET websites + timing REST API + workers + SQL DB
```

Infra for the AKS side lives in `kc-racemonitor-terraform` (composition) +
`kc-racemonitor-terraform-modules` (module library). The two RMonitor
protocol spec PDFs are checked into `kc-racemonitor-relay` and
`kc-racemonitor-web` roots — consult them before touching feed-parsing code.

## Conventions

- **Remote**: all repos live at `git@github.com:KartingCoach/<repo>.git`;
  default branch is `master` everywhere.
- **Branch naming**: router default (short conventional slug).
- **Cloud**: **Azure** (AKS, classic Cloud Services, ACR
  `racemonitor.azurecr.io`, Azure Storage/KeyVault) with **Cloudflare** DNS
  for `race-monitor.com`. No AWS.
- **CI**: **Concourse** where CI exists at all
  (`kc-racemonitor-terraform/rm-cluster/concourse-ci/`, CI base images in
  `kc-racemonitor-services`). Most repos have no CI — verify locally before
  pushing.
- **Observability**: Datadog (autodiscovery annotations hardcoded in
  `kc-racemonitor-terraform-modules/create-deployment`), Elmah + NewRelic on
  the .NET side.
- **Committed secrets are endemic** — plaintext storage access keys in
  `backend.tfvars`, Redis passwords in `azure-kube.yaml`, code-signing
  certs/`.pfx` files, hardcoded RTMP and DB credentials. Assume they're
  live: never paste them into output, PRs, or external services, and don't
  add new ones. Flag opportunities to remediate rather than working around
  silently.
- **Legacy toolchains dominate.** Much of this workspace (.NET Framework,
  Flash/Flex, Node 0.x) cannot be built or run on this Linux machine.
  Confirm the toolchain exists before promising to build/test; often the
  honest answer is "edit + review only, build happens on Windows/macOS."
- **Untracked config**: `kc-racemonitor-server` uses gitignored `*.local.js`
  / `server_config.js` / `relay-config.js` files — copy them into worktrees
  per the router's env-file convention.
- **Never run** `kc-racemonitor-server/startrelay.sh` on a shared host — it
  does `killall -9 node`.

## Reference files

Structured cached lookups live under `.claude/references/` (same convention
as the flocasts workspace). None exist yet — when you probe something
expensive and reusable (e.g., Azure resource inventories, Concourse pipeline
details), snapshot it there with a `_probedAt` date field and add a row to a
table in this section.
