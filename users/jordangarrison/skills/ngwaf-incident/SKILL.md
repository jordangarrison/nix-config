---
name: ngwaf-incident
description: Fastly Next-Gen WAF (NGWAF, Signal Sciences) rule work during an incident. Use when blocking a crawler or bot with an NGWAF rule, rolling a rule back, proving what a rule blocked, checking which rules act on a signal, or pulling flagged requests when the WAF's request search fails. Needs curl, jq, and an NGWAF API key. Read-only edge triage with no rule change belongs to using-sigsci-waf.
---

# NGWAF incident

Every call goes through `scripts/ngwaf.sh` in this skill's directory; `ngwaf.sh help` gives exact syntax. The helper needs an NGWAF API key, kept in 1Password or in a local file with mode 600, whichever the user chooses. It hands the key to curl on stdin, so the key stays out of argv, output, and files. Reach the API only through the helper, and leave the key's source (the `op` item or the file) unread by any other command.

## 1. Check the setup cache

Run `ngwaf.sh auth-test`. It reads the setup cache, makes one cheap call to the site, and prints the API user, corp/site, `agentLevel`, and block code.

| Exit | Meaning | Next |
|---|---|---|
| 0 | Cache and key work. The cache's verified-at time is updated. | Continue. If `agentLevel` is not `block`, tell the user: no rule on this site blocks anything. |
| 3 | No cache, or it lacks a field. | Run setup. |
| 4 | Key unreadable (op signed out, file missing or not mode 600) or rejected. | Fix the stated cause, or run setup. |
| other | Network or API error. | Retry once, then report the error. |

**Setup.** Ask the user for the key source and the target, then run one of:

```bash
ngwaf.sh setup --op 'op://<vault>/<item>/<field>' [--op-account <account>] --corp <corp> --site <site> --user <api-user-email>
ngwaf.sh setup --file <path-to-600-file> [--var <NAME>] [--corp <corp> --site <site> --user <email>]
```

A `--file` may hold the bare key, or `NAME=value` lines; the variable defaults to `SIGSCI_TOKEN`, and `SIGSCI_CORP`, `SIGSCI_SITE`, and `SIGSCI_EMAIL` in the same file fill the other flags. Setup writes the cache, keeps any previous one as `config.prev`, and runs auth-test. The step is done when auth-test exits 0.

The cache is `~/.config/sigsci/config` (override with `SIGSCI_CONFIG`). It holds only where the key is, the corp, site, API user, and verified-at time. using-sigsci-waf uses the same file, and its 1Password caches load here unchanged. `SIGSCI_SITE=<site> ngwaf.sh ...` targets another site for one call without touching the cache.

## 2. Reach for the command that fits

Times are unix seconds, `-30m`, `-2h`, `-1d`, or ISO-8601 UTC (`2026-10-27T00:40:00Z`).

| Need | Command |
|---|---|
| Every rule, its signals, and whether any enabled block rule matches each signal | `rules` (`--json` for the normalised list) |
| All flagged requests in a window, as NDJSON | `feed FROM UNTIL > file.ndjson` |
| Counts per signal over time (`BLOCKED`, `site.<name>`, system signals) | `timeseries TAG[,TAG] [FROM] [UNTIL] [ROLLUP]` |
| Quick search in NGWAF query syntax | `search "from:-30min httpcode:406" [LIMIT]` |
| What one rule did, and what its fingerprint missed | `verify-rule ID FROM UNTIL [--host HOST] [--ua REGEX]` |
| Create a rule / turn one off (guarded, section 3) | `create FILE` / `disable ID` |
| Any other read | `get /site-path` or `corp-get /corp-path` |

Feed facts the API enforces: `until` must be 5 or more minutes ago (the helper moves it back and says so), times fall on minute boundaries (the helper rounds), the window is at most 24 h, and `from` is at most 7 days ago. The feed pages through `next.uri` until the window is exhausted, 1,000 records a page, with up to 180 s per page. A busy site yields thousands of flagged requests a minute, so keep windows to the minutes you need and write the output to a file. Exit 2 means a page failed and the output is truncated; say so in anything built on it. Each record carries `serverName`, `path`, `userAgent`, `responseCode`, `remoteIP`, `headersIn` (`[name, value]` pairs), and `tags`, where `tags[].detector` is the ID of the rule that added the tag.

`search` has returned HTTP 500 for whole incidents while `feed` kept working. When search fails, use feed.

`verify-rule` attributes requests to the rule by `tags[].detector`, not by status code: every block rule on a site returns the same code (406 by default), so a 406 alone proves nothing. Counts are lower bounds, because the feed holds flagged requests only and `requestLogging: sampled` logs a sample.

Feed records hold client IPs and request headers: keep raw feed files out of repositories and shared channels, and share counts.

## 3. Writes: create and disable

`create` and `disable` are dry runs by default: they print the target corp/site, the method and path, and the body or change, and send nothing. They send only when `SIGSCI_ALLOW_WRITE` equals the target site name, so a write meant for one site cannot land on another. They need a write-capable API user.

Before setting `SIGSCI_ALLOW_WRITE`, show the user the dry-run output and the evidence for the change (for a block, the collateral count from the playbook), then get their go-ahead. With `--yolo`, skip the go-ahead; the dry run and the collateral check still run and appear in your report, and a nonzero collateral count still stops the write.

- **Create**: write the body from [rule-schema.md](rule-schema.md), then `ngwaf.sh create rule.json`. Report the new ID and the rollback command it prints.
- **Rollback**: `ngwaf.sh disable ID` sends the rule back with `enabled: false` and everything else unchanged, then reads it back to confirm. Prefer it to deleting: the rule and its history stay for the write-up, and re-enabling is one control-panel toggle.

Any other change (editing conditions, deleting, corp rules, site settings) goes through the control panel or Terraform.

## Block a crawler or bot during an incident

Follow [playbook-block-crawler.md](playbook-block-crawler.md) step by step before any `create`: fingerprint, collateral check, existing rules, apply, verify, codify.
