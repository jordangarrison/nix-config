#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: deploy-always-on [--build-only] [--no-mac] [flake]

Run on endeavour. Build/check Linux locally and build the Mac over SSH, record
current systems, then LIVE-TEST discovery and endeavour. Ask once before switching
Linux and finally the Mac (interactive password/Homebrew prompts over ssh -t).

--build-only builds/checks Linux locally without contacting any target.
--no-mac skips all Mac checks/builds/switches and permits local-only snapshots.
Otherwise the source must be a clean revision published to the canonical GitHub
repository, so the Mac builds that exact revision without changing its checkout.
The default flake is the current directory. No --yes or unattended mode exists.
See docs/runbooks/deploy.md for bootstrap and upstream rollback limitations.
EOF
}

build_only=false
include_mac=true
while (( $# )); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --build-only) build_only=true; shift ;;
    --no-mac) include_mac=false; shift ;;
    *) break ;;
  esac
done
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
metadata=$(nix flake metadata --json --no-update-lock-file "$flake")
snapshot=$(jq -er '.path | select(startswith("/nix/store/"))' <<< "$metadata")
mac_ssh=jordan.garrison@h952l3dphh
if $include_mac && ! $build_only; then
  rev=$(jq -r '.revision // empty' <<< "$metadata")
  if [[ ! $rev =~ ^[0-9a-f]{40}$ ]]; then
    echo 'Mac deployment requires a clean committed Git revision; commit and push, or use --no-mac.' >&2
    exit 1
  fi
  mac_flake="git+ssh://git@github.com/jordangarrison/nix-config?allRefs=1&rev=$rev"
  # Fetch this immutable revision from the canonical remote, not a local branch
  # or the Mac's checkout. Failure (including an unpushed SHA) must fail closed.
  if ! published=$(nix flake metadata --json --refresh --no-update-lock-file "$mac_flake"); then
    echo 'Cannot verify the revision on GitHub. Push it first, or use --no-mac.' >&2
    exit 1
  fi
  published_rev=$(jq -er '.revision | strings' <<< "$published")
  published_hash=$(jq -er '.locked.narHash | strings' <<< "$published")
  local_hash=$(jq -er '.locked.narHash | strings' <<< "$metadata")
  if [[ $published_rev != "$rev" || $published_hash != "$local_hash" ]]; then
    echo 'Local snapshot differs from the published revision; refusing mixed Linux/Mac sources.' >&2
    exit 1
  fi
  printf 'Mac and Linux source revision: %s\n' "$rev"
fi
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
if $include_mac; then
  # No TTY needed for this read-only preflight. pwd -P resolves the Darwin link
  # without relying on GNU readlink; require the expected machine and nh first.
  if ! current=$(ssh "${ssh_opts[@]}" "$mac_ssh" \
    'test "$(uname -s)" = Darwin && test "$(hostname -s | tr "[:lower:]" "[:upper:]")" = H952L3DPHH && command -v nh >/dev/null && cd /run/current-system && pwd -P'); then
    echo 'Mac is unreachable or not ready. No live tests have started; use --no-mac for Linux only.' >&2
    exit 1
  fi
  if [[ $current != /nix/store/* || $current == *$'\n'* ]]; then
    echo 'Invalid Mac current-system path; stopping before live tests.' >&2
    exit 1
  fi
  printf 'H952L3DPHH (%s): %s\n' "$mac_ssh" "$current" | tee -a "$record"
  printf 'Recovery (on Mac, approved manually): sudo env HOME=/var/root %s/activate\n' "$current" | tee -a "$record"
  printf 'Mac source: %s\n' "$mac_flake" | tee -a "$record"
  echo 'Building on the Mac before live tests (no activation).'
  # mac_flake is a fixed URL plus a validated hexadecimal SHA; quote its '&'.
  # shellcheck disable=SC2029
  if ! ssh -t "${ssh_opts[@]}" "$mac_ssh" \
    "nh darwin build '$mac_flake' -H H952L3DPHH --no-nom --no-update-lock-file"; then
    echo 'Mac build failed. No live tests or switches ran; use --no-mac for Linux only.' >&2
    exit 1
  fi
else
  echo 'Mac excluded by --no-mac; deploying Linux only.'
fi
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
if $include_mac; then
  printf '\nCheck Linux services. Switch Linux, then Mac (sudo/Homebrew prompts)? [y/N] '
else
  printf '\nCheck services on both hosts. Switch both and update boot loaders? [y/N] '
fi
answer=''
read -r answer || true
case "$answer" in
  y|Y|yes|YES)
    deploy --skip-checks --targets "${targets[@]}" -- "${nix_args[@]}"
    if $include_mac; then
      echo 'Linux switched. Switching Mac last; enter its sudo password in the SSH terminal.'
      # shellcheck disable=SC2029
      if ssh -t "${ssh_opts[@]}" "$mac_ssh" \
        "nh darwin switch '$mac_flake' -H H952L3DPHH --no-nom --no-update-lock-file --elevation-strategy /usr/bin/sudo"; then
        echo 'Mac switch completed.'
      else
        status=$?
        printf 'ERROR: Mac switch failed (exit %s). Linux switches remain applied; no Linux rollback attempted. Recovery paths: %s\n' "$status" "$record" >&2
        exit "$status"
      fi
    fi
    ;;
  *)
    printf 'No switch. Live tests remain active; recovery paths: %s\n' "$record"
    ;;
esac
