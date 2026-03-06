# Forgejo Action Runners Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable Forgejo Actions and configure both Docker-based and native action runners on the endeavour host.

**Architecture:** Add Actions settings to the existing Forgejo module, create a new `forgejo-runner.nix` module with two runner instances (docker and native), and wire it into the endeavour host in `flake.nix`. Secrets follow the existing `/var/lib/<service>-secrets/` convention used by ACME.

**Tech Stack:** NixOS, `services.gitea-actions-runner` module, `pkgs.forgejo-runner`, Docker

---

### Task 1: Enable Actions in Forgejo Settings

**Files:**
- Modify: `modules/nixos/forgejo.nix:19-35`

**Step 1: Add actions settings block**

In `modules/nixos/forgejo.nix`, add an `actions` block inside `settings`, after the opening `settings = {` on line 19:

```nix
    settings = {
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "github";
      };

      server = {
        # ... existing server settings unchanged
```

This enables the Actions feature in Forgejo and configures bare action references (e.g. `actions/checkout@v4`) to resolve against GitHub.

**Step 2: Verify the flake builds**

Run: `nh os build .`
Expected: Build succeeds with no errors.

**Step 3: Commit**

```bash
git add modules/nixos/forgejo.nix
git commit -m "feat(forgejo): enable Actions with GitHub action URL resolution"
```

---

### Task 2: Create the Forgejo Runner Module

**Files:**
- Create: `modules/nixos/forgejo-runner.nix`

**Step 1: Create the runner module**

Create `modules/nixos/forgejo-runner.nix` with two runner instances:

```nix
{ config, lib, pkgs, ... }:

{
  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;

    instances = {
      docker = {
        enable = true;
        name = "endeavour-docker";
        url = "https://forgejo.jordangarrison.dev";
        tokenFile = "/var/lib/forgejo-runner-secrets/token";
        labels = [
          "ubuntu-latest:docker://node:22-bookworm"
          "ubuntu-22.04:docker://node:20-bookworm"
        ];
        settings = {
          runner.timeout = "3h";
          runner.shutdown_timeout = "3h";
          cache.enable = true;
        };
      };

      native = {
        enable = true;
        name = "endeavour-native";
        url = "https://forgejo.jordangarrison.dev";
        tokenFile = "/var/lib/forgejo-runner-secrets/token";
        labels = [ "native:host" ];
        hostPackages = with pkgs; [
          bash
          coreutils
          curl
          gawk
          git
          git-lfs
          gnused
          nodejs
          wget
          nix
        ];
        settings = {
          runner.timeout = "3h";
          runner.shutdown_timeout = "3h";
        };
      };
    };
  };

  # Grant Docker access to the docker runner instance
  systemd.services."gitea-runner-docker".serviceConfig.SupplementaryGroups = [ "docker" ];
}
```

Key details:
- `services.gitea-actions-runner` is the NixOS module name (there is no `forgejo-actions-runner` module)
- `package = pkgs.forgejo-runner` swaps in the Forgejo-compatible runner binary
- Token file at `/var/lib/forgejo-runner-secrets/token` must contain `TOKEN=<value>` (systemd EnvironmentFile format)
- Docker instance maps `ubuntu-latest` and `ubuntu-22.04` to Debian Bookworm-based Node.js images
- Native instance provides common CLI tools plus `nix` for Nix-aware workflows
- `SupplementaryGroups` grants the docker runner service access to the Docker socket

**Step 2: Verify the flake builds**

Run: `nh os build .`
Expected: Build succeeds. (Runner won't start without the token file, but the build should work.)

**Step 3: Commit**

```bash
git add modules/nixos/forgejo-runner.nix
git commit -m "feat(forgejo): add Docker and native action runner module"
```

---

### Task 3: Wire Runner Module into Endeavour Host

**Files:**
- Modify: `flake.nix:105`

**Step 1: Add the import**

In `flake.nix`, add the runner module import right after the `forgejo.nix` import (line 105):

```nix
            ./modules/nixos/forgejo.nix
            ./modules/nixos/forgejo-runner.nix
            ./modules/nixos/virtualization.nix
```

**Step 2: Verify the full flake builds**

Run: `nh os build .`
Expected: Build succeeds with no errors.

**Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(endeavour): enable forgejo action runners"
```

---

### Task 4: Manual Post-Deploy Setup (on endeavour host)

> These steps are performed **after** `nh os switch .` on the endeavour host. They are not automatable via Nix.

**Step 1: Create the secrets directory and token file**

```bash
sudo mkdir -p /var/lib/forgejo-runner-secrets
sudo chmod 700 /var/lib/forgejo-runner-secrets
```

**Step 2: Get a registration token from Forgejo**

In the Forgejo web UI: **Site Administration → Actions → Runners → Create new Runner**

Copy the token.

**Step 3: Write the token file**

```bash
sudo sh -c 'echo "TOKEN=<paste-your-token-here>" > /var/lib/forgejo-runner-secrets/token'
sudo chmod 600 /var/lib/forgejo-runner-secrets/token
```

**Step 4: Switch and verify**

```bash
nh os switch .
```

Check both runner services:

```bash
systemctl status gitea-runner-docker
systemctl status gitea-runner-native
```

Look for "Runner registered successfully" in the logs:

```bash
journalctl -u gitea-runner-docker -f
journalctl -u gitea-runner-native -f
```

Verify both runners appear as **Online** in Forgejo UI: **Site Administration → Actions → Runners**

**Step 5: Test with a workflow**

Create `.forgejo/workflows/test.yml` in any repo:

```yaml
name: Test Runner
on: [push]

jobs:
  docker-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Hello from Docker runner!"
      - run: node --version

  native-test:
    runs-on: native
    steps:
      - uses: actions/checkout@v4
      - run: echo "Hello from native runner!"
      - run: nix --version
```

---

### Troubleshooting Reference

| Problem | Fix |
|---------|-----|
| "unregistered runner" error | `sudo rm /var/lib/private/gitea-runner/{docker,native}/.runner` then restart services |
| Token file format wrong | Must be `TOKEN=<value>`, not bare token |
| Docker socket denied | Reboot after first deploy (group membership change) |
| Labels changed but not updating | Delete `.runner` file and restart service |
