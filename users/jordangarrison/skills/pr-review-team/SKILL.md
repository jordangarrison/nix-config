---
name: pr-review-team
description: Use when reviewing a PR for an Ash/Phoenix project and you want a multi-perspective expert review. Dispatches 4 parallel agents - Ash framework, UI/LiveView, security, and performance/SRE - each with domain-specific checklists. Use before merging features, after completing major work, or when the user asks for a thorough review.
---

# PR Review Team

Dispatch 4 specialized review agents in parallel for comprehensive Ash/Phoenix PR review.

## When to Use

- Before merging a feature branch
- User asks for a "review", "thorough review", or "expert review"
- After completing a major implementation

## Process

1. **Gather context** — PR details, diff stats, read key source files
2. **Dispatch 4 agents** in parallel using `superpowers:code-reviewer` subagent type
3. **Compile report** — deduplicate findings, classify severity, produce unified action plan

## Step 1: Gather Context

```bash
gh pr view --json number,title,body,url,baseRefName,headRefName
git log --oneline main..HEAD | head -30
git diff --stat main..HEAD
```

Read all new/changed source files (resources, LiveViews, components, tests, migrations).

## Step 2: Dispatch Agents

Launch all 4 as background agents using `subagent_type: "superpowers:code-reviewer"`. Each gets the full file list and a domain-specific checklist. See `agent-prompts.md` for the prompt templates.

**Agent roles:**

| Agent | Focus Areas |
|-------|------------|
| **Ash Expert** | Resource design, policies, actions, PubSub, domain registration, Ash.Type.Enum usage, identity constraints, AshPhoenix.Form |
| **UI/LiveView Expert** | LiveComponent patterns, streams, HEEx correctness, hooks, accessibility, form handling, presence UX |
| **Security** | Authorization policies, input validation, XSS, PubSub security, race conditions, data exposure, OWASP |
| **Performance/SRE** | N+1 queries, index coverage, PubSub scalability, pagination, memory, telemetry, operational concerns |

## Step 3: Compile Report

When all agents complete, produce a unified report:

1. **Verdict** — Ready to merge / Needs changes / Needs significant rework
2. **Critical** — Must fix (consensus items first)
3. **Important** — Should fix (with which reviewers flagged each)
4. **Minor** — Follow-up items table
5. **Positives** — What was done well
6. **Action plan** — Ordered fix list with effort estimates

Deduplicate findings flagged by multiple reviewers and note consensus.

## Common Mistakes

- Sending agents without reading the files first (they need file paths in prompts)
- Not including test files in the review scope
- Forgetting to include migration files for the security/performance reviewers
- Not running `mix usage_rules.search_docs` in the Ash agent prompt for best-practice verification
