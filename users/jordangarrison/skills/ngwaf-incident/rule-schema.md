# Site rule body

The body `ngwaf.sh create` sends (`POST /corps/<corp>/sites/<site>/rules`). Start from [examples/block-crawler-rule.json](examples/block-crawler-rule.json). `rules --json` and `get /rules/<id>` show live rules in the same shape.

## Top level

| Field | Value |
|---|---|
| `type` | `request` for a match-and-act rule; `rateLimit` for a rate limit |
| `enabled` | `true` |
| `groupOperator` | `all` (every condition) or `any` |
| `conditions` | at least one condition (below) |
| `actions` | at least one action (below) |
| `reason` | why the rule exists: fingerprint, incident, date |
| `requestLogging` | `sampled` (default) or `none`. `sampled` is what makes the rule's hits visible in the feed |
| `expiration` | `""` for always on |
| `signal` | rate-limit rules only: the signal the rule attaches when it trips |

The server sets `id`, `siteNames`, `created`, `createdBy`, and `updated`; `create` rejects a body with an `id`.

## Conditions

```json
{ "type": "single", "field": "useragent", "operator": "equals", "value": "<exact UA>" }
{ "type": "group", "groupOperator": "any", "conditions": [ <single>, <single> ] }
{ "type": "multival", "field": "requestHeader", "operator": "doesNotExist", "groupOperator": "all",
  "conditions": [ { "type": "single", "field": "name", "operator": "equals", "value": "Referer" } ] }
{ "type": "multival", "field": "signal", "operator": "exists", "groupOperator": "all",
  "conditions": [ { "type": "single", "field": "signalType", "operator": "equals", "value": "SUSPECTED-BAD-BOT" } ] }
```

- `single` fields: `scheme`, `method`, `path`, `useragent`, `domain`, `ip`, `responseCode`, `agentname`, `paramname`, `paramvalue`, `country`, `signalType`, `ja3Fingerprint`, `ja4Fingerprint`.
- `multival` fields: `requestHeader`, `responseHeader`, `requestCookie`, `queryParameter`, `postParameter`, `signal`; the inner conditions test `name` and `valueString`/`valueInt`/`valueIp`.
- Operators: `equals`, `doesNotEqual`, `contains`, `doesNotContain`, `matches`, `doesNotMatch` (regex), `like`, `greaterEqual`, `lesserEqual`, `exists`, `doesNotExist`, `inList`, `notInList`.

Prefer `equals` on exact user-agent strings over a `matches` regex: an exact string cannot catch a real browser by accident. Anchor path regexes (`^/teams/[^/]+/videos?$`).

## Actions

| Action | Effect |
|---|---|
| `{ "type": "block" }` | Return the site's block code (406 unless the site sets another; `responseCode` overrides it) |
| `{ "type": "addSignal", "signal": "site.<name>" }` | Tag only. Blocks nothing unless an enabled block rule matches the signal (check with `rules`). The signal must already exist on the site. |
| `{ "type": "allow" }` | Let the request through other rules |
| `{ "type": "browserChallenge" }` | Challenge instead of block |

A block rule can carry both `block` and `addSignal`, so its hits are countable with `timeseries site.<name>`.

## Rate-limit rules

`type: rateLimit`, a top-level `signal: "site.<name>"` (create the signal first), actions `logRequest` (observe) or `blockSignal` (enforce), and `"rateLimit": { "threshold": N, "interval": 1 | 10, "duration": 300..86400, "clientIdentifiers": [ { "type": "ip" } ] }`. `interval` is minutes; `clientIdentifiers` is required. A sustained 429 or 503 to a verified search crawler drops pages from its index, so rate-limit real crawlers only with care.
