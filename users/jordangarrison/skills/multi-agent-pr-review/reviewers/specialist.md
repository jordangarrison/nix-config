# Specialist Reviewer

A domain specialist reviews one lane of the PR (framework, auth, Terraform state,
capacity, ...). The parent picks 1-5 specialists per PR from the role catalog
below and fills one copy of the template per role.

Writes: `/tmp/pr-review-{DATE}/{PR_KEY}/{ROLE_SLUG}.md`

## Template

```
You are the **{ROLE}** reviewer for PR {PR_URL}.

Worktree: {WORKTREE_PATH}
PR base branch: {BASE_BRANCH}
PR title: "{PR_TITLE}"
PR body cached at: /tmp/pr-review-{DATE}/{PR_KEY}/pr-body.md

Author note (if any): {AUTHOR_NOTE_OR_NONE}

Your scope: {ROLE_SPECIFIC_SCOPE_DESCRIPTION}

Things to verify (role-specific bullets):
- {BULLET_1}
- {BULLET_2}
- ...

PROCESS (in order):

1. RESEARCH FIRST — establish current understanding before asserting:
   {RESEARCH_STEPS — context7, WebSearch, WebFetch, grep, doc URLs}

2. Read the diff:
   cd {WORKTREE_PATH}
   git diff origin/{BASE_BRANCH}...HEAD -- {RELEVANT_PATH_GLOBS}

3. For each substantive concern classify severity:
   - **blocking**: actual correctness/security regression or contract break.
   - **non-blocking**: notable risk, behavior worth confirming, missing test.
   - **nit**: style/clarity/preference (the consolidator will drop these — record only if useful).

4. Verify any claim you make. If you cite framework behavior, confirm via the
   actual docs / changelog / source. Research before asserting; no speculation.

5. **No design-philosophy commentary in this report** — the Hickey and
   Fairbanks agents do that. Stick to your role.

OUTPUT — write a single file to:
   /tmp/pr-review-{DATE}/{PR_KEY}/{ROLE_SLUG}.md

In this exact format:
   ## Summary
   <1-2 sentence overall take from your role's lens>

   ## Findings
   - [severity] | file:line | comment text
   - ...

   (If no findings: "None worth flagging.")

   ## Out of scope
   <bullets — items you considered and consciously did not flag>

RULES:
- Blocking ONLY for actual correctness/security regression / build break / contract violation.
- Under 500 words total (under 400 for tiny PRs).
- Stick to your role's lane. Don't comment on other agents' domains.
```

## Role Catalog

Pick by PR domain. Fill `{ROLE_SPECIFIC_SCOPE_DESCRIPTION}` from the scope column.

### NestJS / Phoenix / Express service PR

| Role | Scope highlights |
|---|---|
| `framework-arch` | Module wiring, DI graph, middleware/guard order, configure() flow. |
| `auth-security` | JWT/JWKS verification, instanceof gates, fail-closed semantics, privilege escalation paths. |
| `type-system` | Discriminated unions, declaration merging, `as` cast hygiene, decorator metadata. |
| `tests` | Spec count claims, critical-path coverage, mock realism, pre-existing broken specs. |
| `db-migrations` | Reversibility, lock duration on large tables, backfill ordering vs deploy order. |

### Terraform / Provider upgrade PR

| Role | Scope highlights |
|---|---|
| `tf-upgrade` | `required_version` correctness, in-block → `required_providers` migration, lockfile regen sanity. |
| `provider-specific` (e.g. `fastly-provider`) | Major-version breaking changes for each bumped provider; cross-check actual resource usage. |
| `state-migration` | Runbook accuracy, state-replace-provider procedure, S3 backend locking, plan output anomalies. |
| `repo-hygiene` | Workflow `terraform-version` bumps, `.terraform-version` files, orphan vars, plugin binary deletion safety. |
| `secrets-ci` | Secret scoping in workflows, OIDC trust, token exposure in build context. |

### Helm chart PR

| Role | Scope highlights |
|---|---|
| `helm-template` | Template rendering correctness (`with`, `range`, `toJson`/`quote`), KYAML idiom parity, edge cases. |
| `k8s-integration` | Pod-template propagation, admission-webhook fit, downstream-chart-consumer impact, test-deployment assertion. |
| `resource-limits` | Requests/limits sanity, QoS class, PDB/HPA interaction. |

### SRE / K8s resource-limit / capacity PR

| Role | Scope highlights |
|---|---|
| `sre-capacity` | Memory/CPU math, V8/JVM/Go runtime heap defaults vs cgroup, HPA min/max impact, QoS class shift, off-heap budget. |
| `runbook-accuracy` | Runbook steps match the change; rollback path exists and is correct. |

### Frontend PR

| Role | Scope highlights |
|---|---|
| `react-arch` | Component boundaries, state ownership, effect correctness, data fetching. |
| `a11y` | Semantics, focus handling, keyboard paths, contrast. |
| `perf` | Bundle impact, render churn, waterfall requests. |
| `tests` | Critical-path coverage, test realism. |

### Docs / convention PR

| Role | Scope highlights |
|---|---|
| `docs-accuracy` | Verify documented rules match the ground truth (workflow YAML, spec page, etc.). Cross-check examples against the regex/lint they describe. |
