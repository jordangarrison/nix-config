# Voyager Installer ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-contained USB installer ISO that fresh-installs the complete voyager system (disko-partitioned SSD + SD card, family `/data` layout, normalized username) with zero building or downloading on the laptop.

**Architecture:** disko is adopted for voyager only (inert for all other hosts). A second nixosConfiguration `voyager-installer` wraps the minimal installer CD and embeds voyager's toplevel closure plus a pre-built disko partition script, exposed as `packages.x86_64-linux.voyager-iso`. A guided `install-voyager` script on the ISO confirms target disks, partitions, installs, and sets Jordan's password.

**Tech Stack:** Nix flakes, disko (nix-community), nixpkgs `installation-cd-minimal.nix`, systemd-tmpfiles.

**Spec:** `docs/superpowers/specs/2026-08-01-voyager-installer-iso-design.md`

**Verification model:** Nix config has no unit tests; the test for each task is `nix eval` of the affected system's drvPath (fast, catches wiring/eval errors) plus full builds at the end. Run all commands from the repo root.

**Known repo gotcha:** module-arg defaults (`foo ? bar`) are NOT honored by the NixOS module system (see comment at `flake.nix:555`). `hosts/voyager/disko.nix` is therefore a plain function imported with explicit args (`import ./disko.nix { }`), never listed directly in `modules`.

---

### Task 1: Add the disko flake input

**Files:**
- Modify: `flake.nix` (inputs block ~line 82, outputs destructure ~line 115)

- [ ] **Step 1: Add the input**

In `flake.nix`, after the `sre-claude-auto-runner` input (line 82-85), add:

```nix
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 2: Add `disko` to the outputs destructure**

In the `outputs = inputs@{ ... }:` argument list, after `sre-claude-auto-runner,` add:

```nix
      disko,
```

- [ ] **Step 3: Lock the new input**

Run: `nix flake lock`
Expected: downloads disko, adds it to `flake.lock`. Then `git diff --stat flake.lock` should show only `flake.lock` changed, and `git diff flake.lock | grep '"disko"'` shows the new node.

- [ ] **Step 4: Verify no other host changed**

Run: `nix eval .#nixosConfigurations.endeavour.config.system.build.toplevel.drvPath`
Expected: prints a `/nix/store/....drv` path with no errors. (The input is inert until imported; this confirms eval still works.)

- [ ] **Step 5: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(flake): add disko input for declarative partitioning"
```

---

### Task 2: Adopt disko for voyager (disk layout + drop UUID mounts)

The layout file and the removal of UUID-based mounts must land together — deleting `fileSystems."/"` without disko in place fails NixOS's root-filesystem assertion.

**Files:**
- Create: `hosts/voyager/disko.nix`
- Modify: `hosts/voyager/hardware-configuration.nix`
- Modify: `flake.nix` (voyager block, ~line 359)

- [ ] **Step 1: Create `hosts/voyager/disko.nix`**

```nix
# Declarative disk layout for voyager (MacBookPro12,1).
#
# Plain function, NOT a NixOS module: the module system ignores arg
# defaults, so the flake imports this as `import ./disko.nix { }`.
# The same file works standalone with the disko CLI, which is the
# escape hatch if device names differ at install time:
#
#   disko --mode destroy,format,mount \
#     --arg ssdDevice '"/dev/sdX"' --arg sdDevice '"/dev/sdY"' \
#     ./disko.nix
{ ssdDevice ? "/dev/sda", sdDevice ? "/dev/sdb", ... }:
{
  disko.devices.disk = {
    # 256 GB internal SSD: ESP + swap + root
    main = {
      type = "disk";
      device = ssdDevice;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "fmask=0077" "dmask=0077" ];
            };
          };
          swap = {
            priority = 2;
            size = "8G";
            content.type = "swap";
          };
          root = {
            priority = 3;
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              extraArgs = [ "-L" "nixos" ];
              mountpoint = "/";
            };
          };
        };
      };
    };

    # 256 GB permanently-inserted SD card: single data partition.
    # nofail: boot proceeds if the card is ever removed.
    sdcard = {
      type = "disk";
      device = sdDevice;
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [ "-L" "sdcard" ];
            mountpoint = "/data";
            mountOptions = [ "nofail" ];
          };
        };
      };
    };
  };
}
```

Note: disko generates `fileSystems` entries that mount by GPT partlabel (`disk-main-root` etc.), so the installed system boots regardless of which `/dev/sdX` names the disks get at runtime. The `ssdDevice`/`sdDevice` args only matter at partition time.

- [ ] **Step 2: Remove UUID mounts from `hosts/voyager/hardware-configuration.nix`**

Delete the `fileSystems."/"`, `fileSystems."/boot"`, and `swapDevices` blocks (lines 17-30). Everything else stays. The resulting file:

```nix
# Do not modify this file!  It was generated by ‘nixos-generate-config’
# and may be overwritten by future invocations.  Please make changes
# to /etc/nixos/configuration.nix instead.
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/hardware/network/broadcom-43xx.nix")
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Filesystems and swap are declared by disko (../voyager/disko.nix);
  # the old UUID-based entries from the previous install were removed.

  # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
  # (the default) this is the recommended approach. When using systemd-networkd it's
  # still possible to use this option, but it's recommended to use it in conjunction
  # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
  networking.useDHCP = lib.mkDefault true;
  # networking.interfaces.wlp3s0.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

- [ ] **Step 3: Wire disko into voyager's module list in `flake.nix`**

In the `"voyager"` block, immediately after `./hosts/voyager/configuration.nix` (line ~390), add:

```nix
            inputs.disko.nixosModules.disko
            (import ./hosts/voyager/disko.nix { })
```

- [ ] **Step 4: Verify voyager evaluates**

Run: `nix eval .#nixosConfigurations.voyager.config.system.build.toplevel.drvPath`
Expected: prints a drv path, no errors.

Run: `nix eval --json .#nixosConfigurations.voyager.config.fileSystems --apply builtins.attrNames`
Expected: JSON list containing `"/"`, `"/boot"`, and `"/data"`.

- [ ] **Step 5: Verify the disko script derivation exists** (the installer embeds it in Task 5)

Run: `nix eval .#nixosConfigurations.voyager.config.system.build.diskoScript.drvPath`
Expected: prints a drv path. If this attribute doesn't exist under this name, check `nix eval .#nixosConfigurations.voyager.config.system.build --apply builtins.attrNames` for the disko-provided script attribute (`diskoScript` / `destroyFormatMount`) and use that name in Task 5.

- [ ] **Step 6: Commit**

```bash
git add hosts/voyager/disko.nix hosts/voyager/hardware-configuration.nix flake.nix
git commit -m "feat(voyager): adopt disko for SSD and SD card layout"
```

---

### Task 3: Normalize Jordan's username on voyager

**Files:**
- Modify: `flake.nix` (voyager users block, ~line 396)

- [ ] **Step 1: Remove the overrides**

In voyager's `users.jordangarrison` block, delete the `username` and `homeDirectory` lines so it reads:

```nix
              users.jordangarrison = {
                enable = true;
              };
```

The module defaults (`users/jordangarrison/nixos.nix:8-18`) then apply: username `jordangarrison`, home `/home/jordangarrison`.

- [ ] **Step 2: Check for stray hardcoded references**

Run: `grep -rn '"jordan"\|/home/jordan\b' flake.nix hosts/voyager/ modules/nixos/`
Expected: no matches (or only matches clearly unrelated to voyager). Fix any voyager-specific hits.

- [ ] **Step 3: Verify eval and username**

Run: `nix eval .#nixosConfigurations.voyager.config.users.users.jordangarrison.home`
Expected: `"/home/jordangarrison"`

- [ ] **Step 4: Commit**

```bash
git add flake.nix
git commit -m "feat(voyager): normalize username to jordangarrison"
```

---

### Task 4: Family group and /data layout

**Files:**
- Modify: `hosts/voyager/configuration.nix`

- [ ] **Step 1: Add the family group and tmpfiles rules**

In `hosts/voyager/configuration.nix`, after the `networking.firewall` block, add:

```nix
  # Shared family storage on the SD card (/data, see disko.nix).
  # tmpfiles re-asserts ownership/modes every boot, so the layout
  # self-heals after the card is reformatted or files are restored.
  users.groups.family.members = [ "jordangarrison" "mikayla" "jane" "isla" ];

  systemd.tmpfiles.rules = [
    "d /data 0755 root family -"
    "d /data/jordangarrison 0755 jordangarrison users -"
    "d /data/mikayla 0755 mikayla users -"
    "d /data/jane 0755 jane users -"
    "d /data/isla 0755 isla users -"
    # setgid + sticky: files inherit the family group; only owners delete.
    "d /data/shared 3775 root family -"
  ];
```

- [ ] **Step 2: Verify eval and group membership**

Run: `nix eval --json .#nixosConfigurations.voyager.config.users.groups.family.members`
Expected: `["jane","isla","jordangarrison","mikayla"]` (order may vary).

- [ ] **Step 3: Commit**

```bash
git add hosts/voyager/configuration.nix
git commit -m "feat(voyager): add family group and shared /data layout"
```

---

### Task 5: Installer ISO configuration

**Files:**
- Create: `hosts/voyager/installer.nix`
- Modify: `flake.nix` (add `voyager-installer` nixosConfiguration after the voyager block; add `packages` output after `homeConfigurations`)

- [ ] **Step 1: Create `hosts/voyager/installer.nix`**

```nix
# Self-contained installer ISO for voyager. Embeds the full voyager
# system closure and a pre-built disko partition script, so the install
# needs no network and no evaluation on the laptop.
#
#   nix build .#voyager-iso
{ pkgs, inputs, voyagerToplevel, voyagerDiskoScript, ... }:
let
  install-voyager = pkgs.writeShellApplication {
    name = "install-voyager";
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root: sudo install-voyager" >&2
        exit 1
      fi

      echo "=== Voyager NixOS installer ==="
      echo
      lsblk -o NAME,SIZE,MODEL,TRAN,TYPE
      echo
      echo "This will DESTROY ALL DATA on:"
      echo "  /dev/sda  (internal 256 GB SSD  -> NixOS: ESP + swap + root)"
      echo "  /dev/sdb  (256 GB SD card       -> /data)"
      echo
      echo "If the lsblk output above does NOT match those devices, ABORT"
      echo "and partition manually with the disko CLI instead:"
      echo "  disko --mode destroy,format,mount \\"
      echo "    --arg ssdDevice '\"/dev/sdX\"' --arg sdDevice '\"/dev/sdY\"' \\"
      echo "    ${./disko.nix}"
      echo "then run: nixos-install --system ${voyagerToplevel} --no-root-passwd"
      echo
      read -rp "Type WIPE to continue: " confirm
      if [ "$confirm" != "WIPE" ]; then
        echo "Aborted."
        exit 1
      fi

      ${voyagerDiskoScript}

      nixos-install --system ${voyagerToplevel} --no-root-passwd

      echo
      echo "Set Jordan's login password:"
      nixos-enter --root /mnt -c 'passwd jordangarrison'

      echo
      echo "Install complete. Set the other users' passwords after first"
      echo "boot with: sudo passwd mikayla   (etc.)"
      read -rp "Reboot now? [y/N] " answer
      case "$answer" in
        y|Y) reboot ;;
        *) echo "Not rebooting." ;;
      esac
    '';
  };
in
{
  isoImage.volumeID = "VOYAGER";
  # The script's references already pull the voyager closure into the
  # ISO store; listing it here makes the intent explicit.
  isoImage.storeContents = [ voyagerToplevel ];
  # Default zstd level is very slow on a ~10-15 GB closure; level 6 is
  # a sane build-time/size trade-off for a throwaway installer image.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  environment.systemPackages = [
    install-voyager
    inputs.disko.packages.${pkgs.system}.disko
  ];
}
```

- [ ] **Step 2: Add the `voyager-installer` nixosConfiguration**

In `flake.nix`, immediately after voyager's closing `};` (before `"discovery"`), add:

```nix
        # Installer ISO for voyager: minimal live CD + the full voyager
        # closure + a guided install script. Built via packages.voyager-iso.
        "voyager-installer" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            voyagerToplevel = self.nixosConfigurations.voyager.config.system.build.toplevel;
            voyagerDiskoScript = self.nixosConfigurations.voyager.config.system.build.diskoScript;
          };
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            ./hosts/voyager/installer.nix
          ];
        };
```

(If Task 2 Step 5 found the disko script under a different `system.build` attribute name, use that here.)

- [ ] **Step 3: Add the `packages` output**

In `flake.nix`, after the `homeConfigurations = { ... };` block (line ~561), add:

```nix
      packages.x86_64-linux.voyager-iso =
        self.nixosConfigurations.voyager-installer.config.system.build.isoImage;
```

- [ ] **Step 4: Verify the installer evaluates**

Run: `nix eval .#packages.x86_64-linux.voyager-iso.drvPath`
Expected: prints a drv path, no errors. (This transitively evaluates voyager itself.)

- [ ] **Step 5: Commit**

```bash
git add hosts/voyager/installer.nix flake.nix
git commit -m "feat(voyager): add self-contained installer ISO with embedded closure"
```

---

### Task 6: Add voyager-installer to CI eval matrix

**Files:**
- Modify: `.github/workflows/pr-validation.yml` (host matrix, ~line 63)

- [ ] **Step 1: Add the matrix entry**

In the NixOS host matrix list containing `- voyager`, add:

```yaml
          - voyager-installer
```

- [ ] **Step 2: Sanity-check the workflow references**

Run: `grep -n "voyager-installer" .github/workflows/pr-validation.yml`
Expected: one match in the matrix. The eval step already interpolates `nixosConfigurations.${{ matrix.host }}`, which resolves for the new name.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/pr-validation.yml
git commit -m "ci: evaluate voyager-installer in PR validation"
```

---

### Task 7: Full build verification

- [ ] **Step 1: Build the voyager system closure**

Run: `nix build .#nixosConfigurations.voyager.config.system.build.toplevel -o /tmp/claude-1000/-home-jordangarrison-dev-jordangarrison-nix-config/20b5c244-3660-4819-b15f-042fc8be8eab/scratchpad/voyager-toplevel`
Expected: completes (mostly cache downloads; custom packages build locally). This is the long pole — expect tens of minutes on first run.

- [ ] **Step 2: Spot-check the built system's fstab**

Run: `grep -E '/data|by-partlabel' /tmp/claude-1000/-home-jordangarrison-dev-jordangarrison-nix-config/20b5c244-3660-4819-b15f-042fc8be8eab/scratchpad/voyager-toplevel/etc/fstab`
Expected: `/`, `/boot`, and `/data` mounted by `/dev/disk/by-partlabel/disk-...` paths; `/data` has `nofail`.

- [ ] **Step 3: Build the ISO**

Run: `nix build .#voyager-iso -o /tmp/claude-1000/-home-jordangarrison-dev-jordangarrison-nix-config/20b5c244-3660-4819-b15f-042fc8be8eab/scratchpad/voyager-iso`
Expected: produces `voyager-iso/iso/*.iso`. Check size: `ls -lh /tmp/claude-1000/-home-jordangarrison-dev-jordangarrison-nix-config/20b5c244-3660-4819-b15f-042fc8be8eab/scratchpad/voyager-iso/iso/` — expect roughly 8-15 GB.

- [ ] **Step 4: (Optional) UEFI boot smoke test in a VM**

Closure inclusion itself needs no check — the install script textually references the toplevel, and Nix guarantees everything it references lands in the ISO's store. What's worth smoke-testing is that the image boots under UEFI:

```bash
nix shell nixpkgs#qemu --command qemu-system-x86_64 -enable-kvm -m 8192 \
  -bios "$(nix build --print-out-paths nixpkgs#OVMF.fd)/FV/OVMF.fd" \
  -cdrom /tmp/claude-1000/-home-jordangarrison-dev-jordangarrison-nix-config/20b5c244-3660-4819-b15f-042fc8be8eab/scratchpad/voyager-iso/iso/*.iso
```

Expected: live system reaches a login prompt; `install-voyager` exists on PATH. (No virtual disks are attached, so running the installer here can't wipe anything — it would just find no `/dev/sda` and the disko step would fail, which is fine for a boot test.) Close the VM window to end the test.

- [ ] **Step 5: Commit any incidental fixes**

If Steps 1-3 required corrections, commit them with messages describing the actual fix. If nothing changed, skip.

---

### Task 8: Flash the USB stick

**Requires the user's USB stick attached and explicit confirmation of the device — this step is destructive and MUST NOT guess the device.**

- [ ] **Step 1: Identify the stick**

Run: `lsblk -o NAME,SIZE,MODEL,TRAN,TYPE,MOUNTPOINTS`
Confirm with the user which device is the stick (e.g. `/dev/sdX`, transport `usb`, size ≥ 16 GB). Do not proceed on ambiguity.

- [ ] **Step 2: Flash**

```bash
sudo dd if=$(ls /tmp/claude-1000/-home-jordangarrison-dev-jordangarrison-nix-config/20b5c244-3660-4819-b15f-042fc8be8eab/scratchpad/voyager-iso/iso/*.iso) of=/dev/sdX bs=4M status=progress oflag=sync
```

Expected: completes without error; `sync` returns promptly afterward.

- [ ] **Step 3: Hand off to the user**

Install procedure on voyager:
1. Insert USB, boot holding **Option (⌥)**, pick the orange EFI/USB entry.
2. Log in to the live console, run `sudo install-voyager`.
3. Confirm the disks (type `WIPE`), wait for install, set Jordan's password when prompted.
4. Reboot into the installed system; set other users' passwords (`sudo passwd mikayla`, etc.).
5. Copy the SD-card backup into `/data/...` — tmpfiles will have created the per-user and shared directories with correct ownership.
