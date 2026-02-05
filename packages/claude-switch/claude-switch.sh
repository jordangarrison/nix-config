#!/usr/bin/env bash

set -euo pipefail

# Claude Code Account Switcher
# Usage: claude-switch <profile>
#        claude-switch save <profile>
#        claude-switch list

CLAUDE_DIR="$HOME/.claude"
CREDS_FILE="$CLAUDE_DIR/.credentials.json"
ACCOUNT_FILE="$CLAUDE_DIR/current-account"

usage() {
    echo "Usage: claude-switch <profile>     Switch to a saved profile"
    echo "       claude-switch save <name>   Save current credentials as profile"
    echo "       claude-switch list          List available profiles"
    echo "       claude-switch current       Show current profile"
    exit 1
}

list_profiles() {
    echo "Available profiles:"
    for f in "$CLAUDE_DIR"/.credentials.*.json; do
        if [[ -f "$f" ]]; then
            name=$(basename "$f" | sed 's/\.credentials\.\(.*\)\.json/\1/')
            if [[ -f "$ACCOUNT_FILE" ]] && [[ "$(cat "$ACCOUNT_FILE")" == "$name" ]]; then
                echo "  * $name (active)"
            else
                echo "    $name"
            fi
        fi
    done
}

save_profile() {
    local name="$1"
    if [[ -z "$name" ]]; then
        echo "Error: Profile name required"
        usage
    fi

    if [[ ! -f "$CREDS_FILE" ]]; then
        echo "Error: No credentials found. Please login first with 'claude login'"
        exit 1
    fi

    cp "$CREDS_FILE" "$CLAUDE_DIR/.credentials.$name.json"
    echo "$name" > "$ACCOUNT_FILE"
    echo "Saved current credentials as '$name'"
}

switch_profile() {
    local name="$1"
    local profile_file="$CLAUDE_DIR/.credentials.$name.json"

    if [[ ! -f "$profile_file" ]]; then
        echo "Error: Profile '$name' not found"
        echo ""
        list_profiles
        exit 1
    fi

    # Save current credentials if we know what profile they belong to
    if [[ -f "$ACCOUNT_FILE" ]]; then
        current=$(cat "$ACCOUNT_FILE")
        if [[ -n "$current" ]] && [[ "$current" != "$name" ]]; then
            cp "$CREDS_FILE" "$CLAUDE_DIR/.credentials.$current.json" 2>/dev/null
        fi
    fi

    # Switch to new profile
    cp "$profile_file" "$CREDS_FILE"
    echo "$name" > "$ACCOUNT_FILE"
    echo "Switched to '$name'"
}

show_current() {
    if [[ -f "$ACCOUNT_FILE" ]]; then
        cat "$ACCOUNT_FILE"
    else
        echo "unknown"
    fi
}

case "${1:-}" in
    "")
        usage
        ;;
    list)
        list_profiles
        ;;
    save)
        save_profile "$2"
        ;;
    current)
        show_current
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        switch_profile "$1"
        ;;
esac
