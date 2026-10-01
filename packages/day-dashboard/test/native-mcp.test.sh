#!/usr/bin/env bash
# Shell-level contract for the dashboard's native Pi MCP collector isolation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
MCP_CONFIG="$WORK/mcp.json"
cat >"$MCP_CONFIG" <<'JSON'
{"mcpServers":{"slack":{"url":"https://example.com/slack"},"linear":{"url":"https://example.com/linear"},"scaleops":{"url":"https://example.com/scaleops","enabled":false}}}
JSON
cat >"$WORK/bin/pi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$WORK/args"
pwd >"$WORK/cwd"
printf '{"items":[]}'
SH
chmod +x "$WORK/bin/pi"
export WORK PATH="$WORK/bin:$PATH"
# shellcheck source=../lib/collect.sh
. "$ROOT/lib/collect.sh"
[ "$(_pi_mcp slack 'Test prompt')" = '{"items":[]}' ]
[ "$(cat "$WORK/cwd")" = "$WORK/mcp-slack" ]
jq -e '.mcpServers.slack.url and .mcpServers.linear.enabled == false and .mcpServers.scaleops.enabled == false' \
  "$WORK/mcp-slack/.pi/mcp.json" >/dev/null
for flag in --no-extensions builtin:mcp builtin:codemode --tools codemode -a; do
  grep -Fx -- "$flag" "$WORK/args" >/dev/null
done
# A disabled server cannot be enabled by choosing it as the collector.
if _pi_mcp scaleops 'Test prompt' >/dev/null; then
  echo 'disabled server was invoked' >&2
  exit 1
fi
printf 'native MCP collector isolation: ok\n'
