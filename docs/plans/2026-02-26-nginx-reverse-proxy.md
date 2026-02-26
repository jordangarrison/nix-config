# Nginx Reverse Proxy with ACME Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a shared nginx reverse proxy module with Cloudflare DNS-01 ACME, and expose greenlight at `greenlight.jordangarrison.dev`.

**Architecture:** A new `modules/nixos/nginx.nix` module handles shared nginx + ACME defaults (Cloudflare DNS-01). Individual service modules (greenlight, and later forgejo etc.) each declare their own `services.nginx.virtualHosts` entry. The Cloudflare API token is stored as a secret file on disk.

**Tech Stack:** NixOS nginx module, NixOS security.acme, Cloudflare DNS-01 (lego provider)

---

### Task 1: Create shared nginx module

**Files:**
- Create: `modules/nixos/nginx.nix`

**Step 1: Write the nginx module**

```nix
{ config, lib, pkgs, ... }:

{
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "jordan@jordangarrison.dev";
      dnsProvider = "cloudflare";
      environmentFile = "/var/lib/acme-secrets/cloudflare-env";
    };
  };
}
```

**Step 2: Create the secrets directory and env file on endeavour**

The file `/var/lib/acme-secrets/cloudflare-env` must contain:

```
CF_DNS_API_TOKEN=<your-cloudflare-api-token>
```

This is a manual step on the target machine:

```bash
sudo mkdir -p /var/lib/acme-secrets
sudo touch /var/lib/acme-secrets/cloudflare-env
sudo chmod 600 /var/lib/acme-secrets/cloudflare-env
# Then edit the file and add: CF_DNS_API_TOKEN=<token>
```

The Cloudflare API token needs `Zone:DNS:Edit` permission for the `jordangarrison.dev` zone.

**Step 3: Commit**

```bash
git add modules/nixos/nginx.nix
git commit -m "feat: add shared nginx reverse proxy module with Cloudflare ACME"
```

---

### Task 2: Import nginx module in endeavour

**Files:**
- Modify: `flake.nix` (endeavour modules list, around line 102)

**Step 1: Add the nginx module import**

Add `./modules/nixos/nginx.nix` to the endeavour modules list in `flake.nix`, right after `./modules/nixos/greenlight.nix`:

```nix
./modules/nixos/greenlight.nix
./modules/nixos/nginx.nix
```

**Step 2: Commit**

```bash
git add flake.nix
git commit -m "feat: import nginx module in endeavour configuration"
```

---

### Task 3: Add greenlight virtual host and update allowedOrigins

**Files:**
- Modify: `modules/nixos/greenlight.nix`

**Step 1: Add the nginx virtual host and update allowedOrigins**

Update `modules/nixos/greenlight.nix` to add the nginx virtual host block and add the new domain to `allowedOrigins`:

```nix
{ config, lib, pkgs, ... }:

{
  services.greenlight = {
    enable = true;
    host = "endeavour";
    port = 4444;
    listenAddress = "0.0.0.0";
    githubTokenFile = "/var/lib/greenlight/secrets/github-token";
    secretKeyBaseFile = "/var/lib/greenlight/secrets/secret-key-base";
    bookmarkedRepos = [
      "jordangarrison/nix-config"
      "jordangarrison/sweet-nothings"
      "jordangarrison/wiggle-puppy"
      "jordangarrison/panko"
      "flocasts/web-monorepo"
      "flocasts/infra-base-services"
      "flocasts/flosports30"
      "flocasts/experience-service"
      "flocasts/helm-charts"
    ];
    allowedOrigins = [
      "//*.ts.net"
      "//endeavour:4444"
      "//greenlight.jordangarrison.dev"
    ];
    followedOrgs = [
      "NixOS"
      "flocasts"
      "milesplit"
      "DirectAthletics"
      "HockeyTech"
      "KartingCoach"
    ];
  };

  services.nginx.virtualHosts."greenlight.jordangarrison.dev" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://localhost:4444";
      proxyWebsockets = true;
    };
  };
}
```

Key additions:
- `"//greenlight.jordangarrison.dev"` in `allowedOrigins` so Phoenix accepts WebSocket connections from the new domain
- `services.nginx.virtualHosts` block that proxies HTTPS traffic to the greenlight service on port 4444, with WebSocket support for Phoenix LiveView

**Step 2: Commit**

```bash
git add modules/nixos/greenlight.nix
git commit -m "feat: add nginx virtual host for greenlight.jordangarrison.dev"
```

---

### Task 4: Build and verify

**Step 1: Build the NixOS configuration**

```bash
nh os build .
```

Expected: Build succeeds with no errors.

**Step 2: Test the configuration**

```bash
nh os test .
```

Expected: Test succeeds. Nginx and ACME services are configured.

**Step 3: Switch (only after build and test pass)**

```bash
nh os switch .
```

**Step 4: Commit any fixups if needed**

---

### Task 5: DNS configuration (manual)

**Step 1: Add DNS record in Cloudflare**

Create an A record in Cloudflare for `greenlight.jordangarrison.dev` pointing to endeavour's Tailscale IP address.

```
Type: A
Name: greenlight
Content: <endeavour-tailscale-ip>
Proxy status: DNS only (gray cloud)
```

Important: Set proxy status to "DNS only" (not proxied) since we're using a Tailscale IP.

**Step 2: Verify ACME certificate**

After DNS propagates and the system is switched, the ACME service should automatically obtain a certificate:

```bash
sudo systemctl status acme-greenlight.jordangarrison.dev
sudo ls /var/lib/acme/greenlight.jordangarrison.dev/
```

**Step 3: Verify access**

```bash
curl -k https://greenlight.jordangarrison.dev
```

Expected: Greenlight responds (may need to be on Tailscale network since DNS points to Tailscale IP).
