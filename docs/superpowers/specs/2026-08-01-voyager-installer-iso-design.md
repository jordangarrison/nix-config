# Voyager Installer ISO — Design

**Date:** 2026-08-01
**Status:** Approved
**Goal:** Fresh-install NixOS on voyager (MacBookPro12,1, 2015) from a self-contained USB installer, with zero compiling or downloading on the laptop.

## Problem

Voyager's CPU is too slow to build the full system closure locally. A fresh install is
needed, so the plan is to build everything on a fast machine and ship it on a bootable
ISO that installs the complete voyager system directly.

Additionally, voyager's current `hardware-configuration.nix` mounts root/boot/swap by
UUID from the previous install. A reformatted disk gets new UUIDs, so the embedded
system would fail to boot unless partitioning and the declared filesystems are
reconciled. We adopt disko to make the disk layout declarative and repeatable.

## Decisions made

1. **Target hardware:** the existing voyager config is correct (MacBookPro12,1,
   Broadwell i5, standard x86_64 UEFI). No boot quirks.
2. **Scope:** fresh install only. Ongoing remote deploys (`nixos-rebuild
   --target-host`) are out of scope but this design keeps that door open.
3. **Self-containment:** the full voyager system closure is baked into the ISO.
   Nothing is built or downloaded on the laptop during install.
4. **Partitioning:** disko, adopted for voyager only. Confirmed that adding the disko
   flake input is inert for all other hosts — only hosts importing
   `disko.nixosModules.disko` are affected, and disko never touches disks during a
   normal rebuild.

## Design

### 1. Flake changes (`flake.nix`)

- Add `disko` as a flake input, following `nixpkgs`.
- Voyager's module list additionally imports `inputs.disko.nixosModules.disko` and
  `./hosts/voyager/disko.nix`.
- Add a new nixosConfiguration `voyager-installer` built from
  `installation-cd-minimal.nix` plus `./hosts/voyager/installer.nix`.
- Expose the image as `packages.x86_64-linux.voyager-iso =
  nixosConfigurations.voyager-installer.config.system.build.isoImage` for a simple
  `nix build .#voyager-iso`.

### 2. Disko layout (`hosts/voyager/disko.nix`)

GPT layout on the internal disk, mirroring the current scheme declaratively:

| Partition | Size          | Type | Label   | Mount  |
|-----------|---------------|------|---------|--------|
| ESP       | 1 GiB         | vfat | `boot`  | /boot (fmask/dmask 0077) |
| swap      | 8 GiB         | swap | `swap`  | swap   |
| root      | rest of disk  | ext4 | `nixos` | /      |

- The UUID-based `fileSystems`/`swapDevices` entries in
  `hosts/voyager/hardware-configuration.nix` are removed; disko's generated config
  becomes the source of truth. The rest of `hardware-configuration.nix` (kernel
  modules, broadcom firmware import, microcode) stays.
- The target disk is a parameter: `disko.nix` declares the device via a module
  argument with a sensible default for voyager's internal SSD, and the installer
  script passes the user-confirmed device to `disko` at install time. Nothing is
  hardcoded to an unstable `/dev/sdX` name inside the committed config.
### 2b. SD card (second disko-managed disk)

Voyager has a permanently inserted 256 GB SD card, previously exFAT from its macOS
days. Its data has been backed up externally, so the installer treats it like the
SSD: wipe and format.

- Declared in `disko.nix` as a second disk: single ext4 partition, label `sdcard`,
  mounted at `/data` with `nofail` (boot proceeds if the card is ever removed).
- Its device is likewise a module argument (SD readers enumerate unpredictably),
  confirmed by the installer script alongside the SSD.
- Ownership: `/data` is chowned to Jordan's user post-format by the install script
  (ext4 has real permissions, unlike the old exFAT setup).
- After first boot, the backed-up data is copied back manually.

### 3. Installer ISO (`hosts/voyager/installer.nix`)

- Based on the minimal installer CD module.
- Embeds the voyager toplevel closure via `isoImage.storeContents = [
  nixosConfigurations.voyager.config.system.build.toplevel ]`.
- Ships a guided `install-voyager` script on PATH that:
  1. Shows detected disks and asks the user to confirm both target devices — the
     SSD and the SD card (confirm-the-disk prompt; no silent auto-wipe of either).
  2. Runs `disko` in destroy/format/mount mode against the voyager disko config
     (both disks).
  3. Chowns `/data` to Jordan's user.
  4. Runs `nixos-install --system <embedded voyager toplevel> --no-root-passwd`.
  5. Prints a done message and offers to reboot.
- The script hardcodes the embedded toplevel store path at ISO build time so no
  evaluation happens on the laptop.

### 4. Workflow

```bash
# On a fast machine
nix build .#voyager-iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync

# On voyager: boot USB, then
install-voyager
```

## Constraints and trade-offs

- **Image size:** the voyager closure (GNOME + dev tooling + 4 users' home-manager)
  will produce a large ISO, likely 10–15 GB. Needs a USB stick of at least 16 GB.
  This is accepted.
- **Staleness:** the ISO snapshots the flake at build time. It is an install
  bootstrap, not an update mechanism; after first boot, updates happen normally (and
  will build on the laptop until remote deploys are set up — future work).
- **Users' passwords:** `nixos-install --no-root-passwd` relies on the user modules
  declaring accounts; initial passwords are set the same way as the previous install
  (post-install `passwd` if needed).

## Error handling

- Install script aborts unless the user types the target device name to confirm.
- disko failures (wrong device, mounted filesystems) abort before `nixos-install`.
- If the embedded closure is missing from the ISO store (build misconfiguration),
  the script fails fast with a clear message rather than falling back to network.

## Testing / acceptance

1. `nh os build .` still succeeds for voyager (disko-generated filesystems replace
   the UUID mounts; closure otherwise unchanged).
2. Other hosts' builds are unchanged (spot-check endeavour with `nh os build .`).
3. `nix build .#voyager-iso` produces a bootable image; ISO contains the voyager
   toplevel in its store.
4. Boot the USB on voyager (or a VM with UEFI for a smoke test), run
   `install-voyager`, confirm the machine boots into the full GNOME system with no
   network required during install.

## Future work (explicitly out of scope)

- Remote deploys from endeavour (`nixos-rebuild --target-host` / nh build-host) to
  fix ongoing rebuild pain.
- Extending disko layouts to other hosts and enabling nixos-anywhere.
