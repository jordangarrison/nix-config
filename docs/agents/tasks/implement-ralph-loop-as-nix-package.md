# Task: Implement Ralph Loop as a Nix Package

## Goal
Create a `ralph` executable packaged in my NixOS configuration that implements the Ralph Wiggum iterative AI loop pattern.

## Requirements

### Core Functionality
- Accept a prompt file path or inline prompt as argument
- Loop execution of a configurable AI agent CLI until completion
- Detect completion via configurable completion phrase (default: `<promise>COMPLETE</promise>`)
- Support max iteration limit with sensible default (20)
- Clean output showing iteration count and status

### Agent Configuration
- Default agent command: `claude -p`
- Configurable via:
  - `--agent` flag (e.g., `--agent "goose run"`, `--agent "aider --yes-always"`)
  - `RALPH_AGENT` environment variable
  - Flag takes precedence over env var

### CLI Interface
```
ralph [OPTIONS] <PROMPT_FILE | --prompt "inline prompt">

Options:
  -a, --agent <CMD>           Agent command (default: claude -p, or $RALPH_AGENT)
  -m, --max-iterations <N>    Max iterations before giving up (default: 20)
  -c, --completion <PHRASE>   Completion detection phrase (default: <promise>COMPLETE</promise>)
  -d, --delay <SECONDS>       Delay between iterations (default: 2)
  -p, --prompt <TEXT>         Inline prompt instead of file
  -v, --verbose               Show full agent output each iteration
  -h, --help                  Show help
```

### Example Usage
```bash
# Basic usage with prompt file
ralph PLAN.md

# Different agent
ralph --agent "goose run" PLAN.md

# Inline prompt with custom completion
ralph -p "Fix all linter errors. Output DONE when complete." -c "DONE"

# Via environment
export RALPH_AGENT="aider --yes-always"
ralph PLAN.md
```

## Implementation

### Language
Use bash for simplicity and portability. Keep it under 150 lines.

### Nix Packaging
Create as a standalone derivation that can be added to my NixOS config:
- Place script at `~/nixos-config/packages/ralph/default.nix` (or similar)
- Script itself at `~/nixos-config/packages/ralph/ralph.sh`
- Wrap with makeWrapper to ensure coreutils/bash available
- Expose as `pkgs.ralph` or overlay

### Output Format
```
═══ Ralph Loop Starting ═══
Agent: claude -p
Max iterations: 20
Completion phrase: <promise>COMPLETE</promise>

─── Iteration 1/20 ───
[agent output or summary]

─── Iteration 2/20 ───
[agent output or summary]

═══ Complete after 2 iterations ═══
```

## On Each Iteration of This Task
1. Check if `~/nixos-config/packages/ralph/` exists
2. Check current state of implementation
3. Implement or fix the next incomplete piece
4. Test by running `nix-build` or `nix eval` to verify syntax
5. If all requirements met and builds successfully, output: <promise>COMPLETE</promise>

## Success Criteria
- [ ] `ralph.sh` implements all CLI options
- [ ] `default.nix` packages it correctly
- [ ] Handles missing prompt file gracefully
- [ ] Handles agent command failure gracefully  
- [ ] Iteration counter and output formatting works
- [ ] Completion detection exits loop correctly
- [ ] Max iterations safety limit works
- [ ] Can be imported into NixOS config

## Notes
- My NixOS config is at `~/nixos-config/`
- I use flakes
- Prefer simple bash over python/rust for this utility
