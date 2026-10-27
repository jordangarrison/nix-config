# Block a crawler during an incident

Six steps, in order. Each ends on its done-condition; carry each step's numbers into the incident channel, since the write-up needs them. Worked example: [examples/block-crawler-rule.json](examples/block-crawler-rule.json), the rule that stopped a video-list crawler on `tv.varsity.com` in a 2026-10-27 incident.

## 1. Fingerprint the crawler

Pull the feed for a few minutes of the attack and group by the request's shape:

```bash
ngwaf.sh feed 2026-10-27T00:30:00Z 2026-10-27T00:35:00Z > /tmp/attack.ndjson
jq -r 'select(.serverName == "HOST")
  | [ .userAgent,
      (.path | gsub("/[0-9]+-[^/]+"; "/:id")),
      (if any(.headersIn[]?; .[0] | ascii_downcase == "referer") then "referer" else "no-referer" end) ]
  | @tsv' /tmp/attack.ndjson | sort | uniq -c | sort -rn | head -20
```

Look for the narrowest combination that covers the attack: exact user-agent strings, a path pattern, and a header the crawler sends or omits (no `Referer`, an odd `Accept-Language`). The 2026-10-27 crawler was two exact Mac Chrome/Edge user agents, on two video-list path shapes, with no `Referer`.

Match on that fingerprint, not on IP or ASN. That crawler rotated through about 4,800 IPs, so IP blocks go stale within minutes, and the hosting ASNs it used also carry VPN and corporate users, so an ASN block hits real people.

Done when you can state the fingerprint as rule conditions, and it covers the bulk of the attack in the feed.

## 2. Check collateral

Count requests over the last 7 days that match the full fingerprint (every condition at once) in traffic history that covers all requests: APM traces, CDN logs, or origin access logs. The NGWAF feed holds flagged requests only, so it cannot show collateral by itself.

Done when the count of fingerprint matches outside the attack is zero, or each one is the crawler. If real users match, narrow the fingerprint and count again; if it cannot be narrowed, stop and take the trade-off to the user.

## 3. Check existing rules first

```bash
ngwaf.sh rules
```

Look for a rule that already targets this crawler (its reason, its fields), especially OBSERVE rules from an earlier wave. An OBSERVE rule only adds a signal. It blocks nothing unless an enabled block rule matches that signal, or a blocking alert (`flagged`, `blockImmediate`) watches it: the `matched by block rules` and `blocking alerts` lines show both. Trust `=> observe only` only when the coverage line is complete. Check whether an old rule still matches the current variant:

```bash
ngwaf.sh verify-rule <old-rule-id> <attack FROM> <attack UNTIL> --host HOST --ua 'REGEX' --path 'REGEX'
```

In 2026-10-27, OBSERVE rules from July for an older variant added `site.bad-bot-traffic`, which no block rule matched, and they matched 0 of 6,229 crawler requests: the variant had changed.

Done when you know whether an existing rule covers the crawler and blocks it. If one does, the problem is elsewhere: stop and report. Otherwise, continue with a new block rule; leave old rules unchanged during the incident.

## 4. Apply

Write the rule body from [rule-schema.md](rule-schema.md), starting from the worked example. Put the fingerprint, the incident, and the date in `reason`, so whoever finds the rule later knows why it exists. Then dry-run it, get the user's go-ahead (or proceed under `--yolo`), and apply:

```bash
ngwaf.sh create rule.json                                # dry run: check target and body
SIGSCI_ALLOW_WRITE=<site> ngwaf.sh create rule.json      # applies; prints ID and rollback
```

Done when the rule ID and its rollback command (`ngwaf.sh disable <id>`) are posted to the incident channel.

## 5. Verify

Check only traffic after go-live. Set FROM to the first minute boundary after the rule went live (`verify-rule` warns if FROM is earlier). The feed serves only windows that end 5 or more minutes ago, so run the check at least 10 minutes after go-live, giving a window of 5 minutes or more:

```bash
ngwaf.sh verify-rule <id> <first minute after go-live> now --host HOST --ua 'REGEX' --path 'REGEX'
```

- **Attributed to this rule**: should be above zero, all with the block code.
- **Candidates not attributed**: these match only the host, UA, and path filters, not the rule's header conditions. Inspect each group. A request the rule was meant to skip (one with a `Referer`, say) is correct. One blocked by another rule says so on its line. Only a request that meets every rule condition and was not blocked is a variant the rule misses.
- **Blocked by other rules**: context only; those rules return the same status code, which is why a status-code count cannot prove this rule worked.

The feed holds flagged, sampled requests, so it cannot show that unflagged traffic stopped; the symptom check below is what proves that.

Then confirm the incident symptom is easing in the system that hurt: origin load, CDN cache misses, 5xx. A block shows up there as a drop; the blocked 406s may not reach logs that keep only 5xx.

Done when the rule has attributed blocks, no inspected candidate is a real miss, and the symptom metric has moved. If the symptom has not moved, the crawler was not the cause, or a variant is leaking: report, and roll back if the rule is not helping.

## 6. Codify

Rules made in the control panel or through the API drift from code. After the incident, move the rule into Terraform with the rest of the NGWAF configuration (at FloSports that work is tracked as SRE-1090), and link the rule ID and incident from the change.

Done when the follow-up ticket exists and names the rule ID.
