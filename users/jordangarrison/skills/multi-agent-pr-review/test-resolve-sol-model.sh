#!/usr/bin/env bash
set -eu

resolver=$(dirname "$0")/resolve-sol-model.sh
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
export PATH="$tmp:$PATH"
cat > "$tmp/pi" <<'EOF'
#!/usr/bin/env bash
[[ $* == '--no-approve --list-models sol' ]] || exit 2
printf '%s\n' "$TEST_CATALOG"
exit "${TEST_PI_STATUS:-0}"
EOF
chmod +x "$tmp/pi"

check() {
  local expected=$1 status=0 actual
  actual=$(TEST_CATALOG=$2 TEST_PI_STATUS=${3:-0} bash "$resolver") || status=$?
  if [[ $status:$actual != "$expected" ]]; then
    printf 'Expected %s, got %s:%s\n' "$expected" "$status" "$actual" >&2
    exit 1
  fi
}

check '0:openai/gpt-6.10-sol' 'provider   model          context  max-out  thinking  images
openai-codex   gpt-99-sol     500K     128K     yes       yes
openai         gpt-6.10-sol   272K     128K     yes       yes
openai         gpt-6-sol      272K     128K     yes       yes
openai         gpt-6.9-sol    272K     128K     yes       yes
openai         gpt-9-sol-preview
openai         gpt-9-luna'
check '0:openai-codex/gpt-6.2-sol' 'openai-codex gpt-6.2-sol
openai-codex gpt-6.1-sol
openai gpt-7-luna
custom gpt-100-sol'
check '1:' 'github-copilot gpt-6-sol'
check '7:' 'openai gpt-6.2-sol' 7
printf 'Sol model resolver checks passed\n'
