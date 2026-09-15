#!/usr/bin/env bash
set -euo pipefail

# Build and launch a test-only NixOS VM with Niri autologin enabled so the
# Noctalia desktop can be inspected without activating the host system.

host="${1:-endeavour}"
case "$host" in
  endeavour|opportunity) ;;
  *)
    echo "usage: $0 [endeavour|opportunity]" >&2
    exit 2
    ;;
esac

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

result="${NOCTALIA_VM_RESULT:-/tmp/noctalia-${host}-vm}"
disk="${NOCTALIA_VM_DISK:-/tmp/noctalia-${host}.qcow2}"
# Test-only credential stored in the VM closure; do not use a real password.
vm_password="vmtest"

printf 'Building interactive %s VM...\n' "$host"
nix build --impure --expr "
let
  flake = builtins.getFlake (toString ./.);
  base = builtins.getAttr \"${host}\" flake.nixosConfigurations;
  vm = base.extendModules {
    modules = [
      ({ lib, ... }: {
        services.displayManager.autoLogin.enable = lib.mkForce true;
        services.displayManager.autoLogin.user = lib.mkForce \"jordangarrison\";
        services.displayManager.defaultSession = lib.mkForce \"niri\";
        users.users.jordangarrison.initialPassword = lib.mkForce \"${vm_password}\";

        # The VM does not contain the canonical live checkout used by the
        # agent-workspaces activation check.
        systemd.services.home-manager-jordangarrison.environment.AGENTS_LIVE_ALLOW_DANGLING = \"1\";
      })
    ];
  };
in
vm.config.system.build.vm
" --out-link "$result"

cat <<EOF

Launching $host with Niri autologin.
Fallback login: jordangarrison / $vm_password
Disk image: $disk
Delete that image to start with a clean VM state.
EOF

export NIX_DISK_IMAGE="$disk"
export QEMU_OPTS="${QEMU_OPTS:--m 16384 -smp 8 -vga none -device virtio-vga-gl -device virtio-tablet-pci -display gtk,gl=on,grab-on-hover=on}"
exec "$result/bin/run-${host}-vm"
