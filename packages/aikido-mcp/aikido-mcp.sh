#!/usr/bin/env bash

set -euo pipefail

# Aikido MCP server (stdio) with its API token read from a fixed path.
# Create the file by hand with mode 0600; it is never in the Nix store.
SECRETS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/aikido/api-key"

if [ -z "${AIKIDO_API_KEY:-}" ] && [ -r "$SECRETS_FILE" ]; then
  AIKIDO_API_KEY="$(tr -d '[:space:]' < "$SECRETS_FILE")"
fi

# Without a token the server still starts, but its browser sign-in needs an
# OS keychain, which NixOS lacks, so every tool call fails there. Warn
# instead of exiting so the client still lists the server.
if [ -n "${AIKIDO_API_KEY:-}" ]; then
  export AIKIDO_API_KEY
else
  echo "aikido-mcp: no token in $SECRETS_FILE; tool calls will fail until it exists" >&2
fi

exec npx -y @aikidosec/mcp "$@"
