#!/usr/bin/env bash
# ralph - Ralph Wiggum iterative AI loop
# Runs an AI agent repeatedly until completion phrase is detected

set -euo pipefail

# Defaults
DEFAULT_AGENT="claude -p"
DEFAULT_MAX_ITERATIONS=20
DEFAULT_COMPLETION="<promise>COMPLETE</promise>"
DEFAULT_DELAY=2

# Configuration (can be overridden by env vars, then by flags)
AGENT="${RALPH_AGENT:-$DEFAULT_AGENT}"
MAX_ITERATIONS="$DEFAULT_MAX_ITERATIONS"
COMPLETION_PHRASE="$DEFAULT_COMPLETION"
COMPLETION_PHRASE_SPECIFIED=false
DELAY="$DEFAULT_DELAY"
VERBOSE=false
PROMPT_FILE=""
INLINE_PROMPT=""

usage() {
    cat <<EOF
ralph - Ralph Wiggum iterative AI loop

Usage: ralph [OPTIONS] <PROMPT_FILE | --prompt "inline prompt">

Runs an AI agent repeatedly until a completion phrase is detected in output.

Options:
  -a, --agent <CMD>           Agent command (default: claude -p, or \$RALPH_AGENT)
  -m, --max-iterations <N>    Max iterations before giving up (default: 20)
  -c, --completion <PHRASE>   Completion detection phrase (default: <promise>COMPLETE</promise>)
  -d, --delay <SECONDS>       Delay between iterations (default: 2)
  -p, --prompt <TEXT>         Inline prompt instead of file
  -v, --verbose               Show full agent output each iteration
  -h, --help                  Show this help

Examples:
  ralph PLAN.md
  ralph --agent "goose run" PLAN.md
  ralph -p "Fix all linter errors. Output <promise>COMPLETE</promise> when done."
  RALPH_AGENT="aider --yes-always" ralph PLAN.md
EOF
    exit 0
}

die() {
    echo "Error: $1" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--agent)
            [[ -n "${2:-}" ]] || die "--agent requires an argument"
            AGENT="$2"
            shift 2
            ;;
        -m|--max-iterations)
            [[ -n "${2:-}" ]] || die "--max-iterations requires an argument"
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        -c|--completion)
            [[ -n "${2:-}" ]] || die "--completion requires an argument"
            COMPLETION_PHRASE="$2"
            COMPLETION_PHRASE_SPECIFIED=true
            shift 2
            ;;
        -d|--delay)
            [[ -n "${2:-}" ]] || die "--delay requires an argument"
            DELAY="$2"
            shift 2
            ;;
        -p|--prompt)
            [[ -n "${2:-}" ]] || die "--prompt requires an argument"
            INLINE_PROMPT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            # Positional argument - treat as prompt file
            if [[ -z "$PROMPT_FILE" ]]; then
                PROMPT_FILE="$1"
            else
                die "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate we have a prompt source
if [[ -z "$INLINE_PROMPT" && -z "$PROMPT_FILE" ]]; then
    die "Must provide either a prompt file or --prompt"
fi

if [[ -n "$INLINE_PROMPT" && -n "$PROMPT_FILE" ]]; then
    die "Cannot specify both prompt file and --prompt"
fi

# If using prompt file, verify it exists
if [[ -n "$PROMPT_FILE" && ! -f "$PROMPT_FILE" ]]; then
    die "Prompt file not found: $PROMPT_FILE"
fi

# Get the prompt content
if [[ -n "$INLINE_PROMPT" ]]; then
    PROMPT="$INLINE_PROMPT"
else
    PROMPT="$(cat "$PROMPT_FILE")"
fi

# Append completion phrase instruction if not specified by user
if ! $COMPLETION_PHRASE_SPECIFIED; then
    PROMPT="$PROMPT

IMPORTANT: When you have completed ALL tasks in this prompt and there is nothing left to do, output exactly: $COMPLETION_PHRASE
Do NOT output this phrase until every single task is fully complete. Only output it once at the very end."
fi

# Print header
echo "═══ Ralph Loop Starting ═══"
echo "Agent: $AGENT"
echo "Max iterations: $MAX_ITERATIONS"
echo "Completion phrase: $COMPLETION_PHRASE"
echo ""

iteration=1
while [[ $iteration -le $MAX_ITERATIONS ]]; do
    echo "─── Iteration $iteration/$MAX_ITERATIONS ───"

    # Create temp file for output
    output_file=$(mktemp)
    trap "rm -f '$output_file'" EXIT

    # Run the agent
    set +e
    if $VERBOSE; then
        # Show output in real-time and capture it
        $AGENT "$PROMPT" 2>&1 | tee "$output_file"
        exit_code=${PIPESTATUS[0]}
    else
        # Capture output silently
        $AGENT "$PROMPT" >"$output_file" 2>&1
        exit_code=$?
    fi
    set -e

    output="$(cat "$output_file")"
    rm -f "$output_file"
    trap - EXIT

    # Check for agent failure
    if [[ $exit_code -ne 0 ]]; then
        echo "Agent exited with code $exit_code"
        if ! $VERBOSE; then
            echo "Last output:"
            echo "$output" | tail -20
        fi
    fi

    # Check for completion
    if echo "$output" | grep -qF "$COMPLETION_PHRASE"; then
        echo ""
        echo "═══ Complete after $iteration iteration(s) ═══"
        exit 0
    fi

    # Show summary if not verbose
    if ! $VERBOSE; then
        # Show last few lines as summary
        line_count=$(echo "$output" | wc -l)
        if [[ $line_count -gt 5 ]]; then
            echo "[...${line_count} lines of output...]"
            echo "$output" | tail -3
        else
            echo "$output"
        fi
    fi

    # Delay before next iteration (unless this was the last one)
    if [[ $iteration -lt $MAX_ITERATIONS ]]; then
        sleep "$DELAY"
    fi

    ((iteration++))
done

echo ""
echo "═══ Max iterations ($MAX_ITERATIONS) reached without completion ═══"
exit 1
