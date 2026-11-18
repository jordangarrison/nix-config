#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: deploy-always-on [--build-only] [flake]

Run on endeavour. Build and check one immutable snapshot locally, record the
current systems, then LIVE-TEST discovery and endeavour over SSH. After tests
pass, ask once before switching both systems and updating their boot loaders.

--build-only builds/checks locally without SSH, copying, testing, or switching.
The default flake is the current directory. No --yes or unattended mode exists.
See docs/runbooks/deploy.md for bootstrap and upstream rollback limitations.
EOF
}

build_only=false
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi
if [[ ${1:-} == --build-only ]]; then
  build_only=true
  shift
fi
if (( $# > 1 )) || [[ ${1:-} == -* ]]; then
  usage >&2
  exit 2
fi
flake=${1:-.}
local_hostname=$(uname -n)
if [[ ${local_hostname%%.*} != endeavour ]]; then
  echo 'Run this command on endeavour (its deploy target is localhost).' >&2
  exit 1
fi
# Do not allow a non-interactive caller to enter the live-test phase.
if ! $build_only && [[ ! -t 0 ]]; then
  echo 'Live deployment needs an interactive terminal; use --build-only for validation.' >&2
  exit 1
fi

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/nix-config/deploy
mkdir -p "$state_dir"
exec 9>"$state_dir/lock"
flock -n 9 || { echo 'Another fleet deployment is running.' >&2; exit 1; }

# Both deployment phases must use exactly what passed the build, even if the
# checkout is edited or an input changes while the operator checks services.
snapshot=$(nix flake metadata --json --no-update-lock-file "$flake" | jq -er '.path | select(startswith("/nix/store/"))')
printf 'Building immutable snapshot: %s\n' "$snapshot"
nix_args=(--no-update-lock-file --option builders '')
nix build --no-link \
  "$snapshot#checks.x86_64-linux.deploy-schema" \
  "$snapshot#checks.x86_64-linux.deploy-activate" \
  "$snapshot#checks.x86_64-linux.deploy-policy" \
  "$snapshot#checks.x86_64-linux.deploy-wrapper" \
  "${nix_args[@]}"
if $build_only; then
  echo 'Local build and deploy checks passed. No target was contacted.'
  exit 0
fi

definition=$(nix eval --json "$snapshot#deploy" "${nix_args[@]}")
mapfile -t ssh_opts < <(jq -r '.sshOpts[]' <<< "$definition")
ssh_user=$(jq -er '.sshUser' <<< "$definition")
# Keep the deploying workstation until last. The policy check also asserts that
# these, and only these, are the fleet's system profiles.
nodes=(discovery endeavour)
targets=()
record=$(mktemp "$state_dir/before-$(date +%Y%m%dT%H%M%S)-XXXXXX.txt")
printf 'Snapshot: %s\n' "$snapshot" | tee "$record"
for node in "${nodes[@]}"; do
  host=$(jq -er --arg node "$node" '.nodes[$node].hostname' <<< "$definition")
  # node is deliberately expanded locally; it is from the fixed names above.
  # shellcheck disable=SC2029
  current=$(ssh "${ssh_opts[@]}" "$ssh_user@$host" \
    "test \"\$(hostname -s)\" = '$node' && readlink -f /run/current-system")
  if [[ $current != /nix/store/* || $current == *$'\n'* ]]; then
    echo "Invalid current-system path from $node; stopping before live tests." >&2
    exit 1
  fi
  printf '%s (%s): %s\n' "$node" "$host" "$current" | tee -a "$record"
  printf 'Recovery (on %s): sudo %s/bin/switch-to-configuration switch\n' "$node" "$current" | tee -a "$record"
  targets+=("$snapshot#$node.system")
done
printf '\nRecovery paths saved to %s\n' "$record"
cat <<'EOF'
LIVE TEST: services can restart now. deploy --test changes the system profile
but does not update the boot loader. Declining the later switch does NOT undo
these live changes. Upstream rollback is not a backup of service data, and a
switch failure after the test may roll back only to the tested generation.
EOF
# Skip only the broad flake check: the four deploy-specific checks above passed.
# Roll back successful earlier targets if a later target fails (upstream default).
deploy --skip-checks --test --targets "${targets[@]}" -- "${nix_args[@]}"
printf '\nCheck services on both hosts. Switch both and update boot loaders? [y/N] '
answer=''
read -r answer || true
case "$answer" in
  y|Y|yes|YES)
    deploy --skip-checks --targets "${targets[@]}" -- "${nix_args[@]}"
    ;;
  *)
    printf 'No switch. Live tests remain active; recovery paths: %s\n' "$record"
    ;;
esac
