# Matt Hartley's "watch" family of read-only diagnostics TUIs:
#
#   netwatch  — network diagnostics (interfaces, connections, packet capture)
#   syswatch  — system diagnostics (CPU, memory, disks, procs, GPU, power)
#   diskwatch — disk diagnostics (usage, IO, hot files, SMART)
#
# All three are Rust and ship their own flake + package.nix upstream, so the
# packages come straight from the flake inputs (see flake.nix) rather than
# being re-packaged in ./packages.
#
# Privileges (nothing here elevates anything — all three run unprivileged and
# degrade gracefully, showing "--" or a one-line note for gated data):
#
#   * netwatch: packet capture and ICMP health probes need root. Upstream
#     documents `sudo setcap 'cap_net_raw,cap_bpf,cap_perfmon+eip'` on the
#     binary, which cannot work here — the store path is read-only and shared,
#     and file capabilities would be lost on every rebuild anyway. Use sudo
#     instead: plain `sudo netwatch` resolves on the NixOS hosts (sudo there
#     inherits PATH and Jordan has passwordless sudo); where sudo sets
#     secure_path (macOS) use `sudo "$(command -v netwatch)"`. The `ebpf`
#     cargo feature is on by default upstream and falls back to ss/lsof
#     attribution when CAP_BPF isn't granted.
#   * syswatch: never needs sudo. On Apple Silicon, temp/fan/per-rail power
#     read `--` because those come from `powermetrics`.
#   * diskwatch: unprivileged it only sees the current uid's processes; the
#     banner counts what it could not read. Exact per-event pid needs
#     fanotify/eBPF (root), so `sudo diskwatch` for that.
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  # Upstream decides which systems it supports: syswatch's flake lists them
  # explicitly (x86_64-linux, aarch64-linux, aarch64-darwin — it deliberately
  # drops x86_64-darwin, which nixpkgs removed in 26.11), while netwatch and
  # diskwatch use flake-utils' default set. Read the `packages` set instead of
  # hardcoding a platform list, so a host on a system a tool doesn't publish
  # simply omits that tool rather than failing to evaluate.
  upstreamPackage = flake: flake.packages.${system}.default or null;

  tools = lib.filter (p: p != null) (
    map upstreamPackage [
      inputs.netwatch
      inputs.syswatch
      inputs.diskwatch
    ]
  );
in
{
  home.packages = tools;
}
