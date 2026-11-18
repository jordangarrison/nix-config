---
description: pstack per-role model choices (overrides skill defaults)
alwaysApply: true
---
# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# Managed by nix-config; do not run /setup-pstack to replace it. Edit the source and rebuild.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model. Alias entries in a panel list still count toward its fan-out.
# Values are pi provider/model with a thinking level.
# Sol runs on provider openai; openai-codex also works.
# defaults: 3
# budget: medium (high)
feature, refactoring: claude-bridge/claude-opus-5-5 high
bug-fix: claude-bridge/claude-opus-5-5 high
perf-issue: openai/gpt-6.1-sol high
hillclimb: openai/gpt-6.1-sol high
judgment and prose: claude-bridge/claude-opus-5-5 high
arena runners: claude-bridge/claude-opus-5-5 high, openai/gpt-6.1-sol high
arena cross-judge pool: openai/gpt-6.1-sol high, claude-bridge/claude-opus-5-5 high
swarm workers: openai/gpt-6.1-sol high
interrogate reviewers: claude-bridge/claude-opus-5-5 high, openai/gpt-6.1-sol high
