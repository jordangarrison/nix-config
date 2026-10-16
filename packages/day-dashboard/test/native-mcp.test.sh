#!/usr/bin/env bash
# Shell-level contract for the dashboard's native Pi MCP collector isolation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
MCP_CONFIG="$WORK/mcp.json"
cat >"$MCP_CONFIG" <<'JSON'
{"mcpServers":{"executor-flo":{"url":"https://example.com/flo/mcp"},"executor":{"url":"https://example.com/mcp"},"retired":{"url":"https://example.com/retired","enabled":false}}}
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
[ "$(_pi_mcp executor-flo 'Test prompt')" = '{"items":[]}' ]
[ "$(cat "$WORK/cwd")" = "$WORK/mcp-executor-flo" ]
jq -e '.mcpServers["executor-flo"].url and .mcpServers.executor.enabled == false and .mcpServers.retired.enabled == false' \
  "$WORK/mcp-executor-flo/.pi/mcp.json" >/dev/null
for flag in --no-extensions builtin:mcp builtin:codemode --tools codemode -a; do
  grep -Fx -- "$flag" "$WORK/args" >/dev/null
done
# A disabled server cannot be enabled by choosing it as the collector.
if _pi_mcp retired 'Test prompt' >/dev/null; then
  echo 'disabled server was invoked' >&2
  exit 1
fi
printf 'native MCP collector isolation: ok\n'
