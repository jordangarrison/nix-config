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
#   * syswatch: never needs sudo, by design — on Apple Silicon its fan, power
#     and GPU-temperature figures come from an unprivileged IOReport + SMC
#     sampler (the `macpow` crate), and Linux reads sysfs. The few figures
#     that genuinely need `powermetrics` (per-component power) render a
#     "needs sudo powermetrics" hint on the tab instead of prompting.
#   * diskwatch: the Hot Files PROCESS column is always an inferred join (no
#     pid rides along on inotify/FSEvents events), sampled every 2s. Exact
#     per-event pid attribution would need fanotify FAN_REPORT_PID or eBPF and
#     is not implemented upstream, so sudo does not buy it — what sudo adds is
#     the same sampled join over *other users'* processes instead of only the
#     current uid. `sudo diskwatch`, or `sudo "$(command -v diskwatch)"` where
#     sudo sets secure_path (macOS). SMART attribute reads also need root.
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

  # diskwatch's SMART tab shells out to a bare `smartctl` (Command::new,
  # resolved off PATH) and upstream's package.nix declares no runtime dep, so
  # out of the box the tab renders a "smartctl not installed" banner unless
  # smartmontools happens to be in the ambient environment. Wrap the binary so
  # smartctl is always there — a PATH prefix baked into the wrapper also holds
  # when diskwatch is invoked by absolute path, which is how it runs under
  # macOS sudo (secure_path) and under `sudo "$(command -v diskwatch)"`.
  withSmartctl =
    pkg:
    pkgs.symlinkJoin {
      name = "diskwatch-smartctl-${pkg.version}";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/diskwatch \
          --prefix PATH : ${lib.makeBinPath [ pkgs.smartmontools ]}
      '';
      inherit (pkg) meta;
    };

  tools =
    lib.concatMap
      (
        tool:
        let
          pkg = upstreamPackage tool.flake;
        in
        lib.optional (pkg != null) ((tool.wrap or lib.id) pkg)
      )
      [
        { flake = inputs.netwatch; }
        { flake = inputs.syswatch; }
        {
          flake = inputs.diskwatch;
          wrap = withSmartctl;
        }
      ];
in
{
  home.packages = tools;
}
