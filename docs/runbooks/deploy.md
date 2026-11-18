# Deploy the fleet from endeavour

Run from the repository root **on endeavour**, in an interactive terminal:

```bash
nix run .#deploy-always-on
```

This is an operator command, not an unattended agent or CI deploy. Starting it
consents to **Linux live testing** (including service restarts) and a remote Mac
build. It asks once before switching Linux and then the Mac. Agents must still
obtain Jordan's permission before entering any activation phase.

For validation without contacting any target:

```bash
nix run .#deploy-always-on -- --build-only
```

For Linux only (for example, while the Mac is offline):

```bash
nix run .#deploy-always-on -- --no-mac
```

Options precede the optional flake argument. `--build-only` always stays local,
regardless of whether `--no-mac` is supplied.

## Fleet and transport

| Node | SSH destination | Why included |
| --- | --- | --- |
| discovery | `jordangarrison@discovery` | Jordan confirmed this is an always-on machine. Tailscale MagicDNS name. |
| endeavour | `jordangarrison@localhost` | Always-on workstation and home-services host; also the build/deploy machine. |
| H952L3DPHH / flomac | `jordan.garrison@h952l3dphh` | Work Mac; attended `nh darwin` over TTY-backed SSH, **not deploy-rs**. Optional with `--no-mac`. |

The wrapper switches discovery, endeavour, then the Mac. The Linux hosts use the
same SSH/sudo/rollback path; there is no hidden local `nh os switch`. Endeavour's
existing SSH alias points to an old Tailscale address, so this draft avoids it
without changing the user's SSH config. Do not run this wrapper from another
machine: `localhost` must be endeavour. A future multi-controller setup should
use a confirmed MagicDNS/FQDN for endeavour instead.

Excluded deliberately:

- **voyager** currently runs Omarchy, per Jordan. Its NixOS configuration,
  including its no-suspend and `machine.type = "desktop"` invariants, is untouched.
- **opportunity** is a laptop, not part of this always-on fleet.
- **jordangarrison@normandy** is standalone Home Manager on WSL/Ubuntu.
  `activate.home-manager` could deploy a user profile, not a NixOS system;
  WSL availability and SSH bootstrap are separate concerns.
- **voyager-installer** is a live installer image, not a deploy target.

## What the command does

1. Refuse another controller, non-interactive execution, or a concurrent fleet
   command. Resolve the selected flake to an immutable Nix-store snapshot.
   With the Mac enabled, require a clean Git revision and fetch that SHA from
   the canonical GitHub remote. Verify the revision **and source NAR hash** match
   the Linux snapshot. Dirty/uncommitted, unpublished, unverifiable, or mismatched
   sources stop the command before contacting any fleet target. `--no-mac` and
   `--build-only` retain local-snapshot support for Linux development.
2. **Build locally**: build `deploy-schema`, `deploy-activate`, `deploy-policy`,
   and `deploy-wrapper`. The activation check depends on **both full Linux system
   closures**, not Darwin. Nix distributed builders are disabled for this phase.
   No fleet target is contacted during this local build.
3. Read each enabled target's hostname and `/run/current-system` over SSH. A wrong
   hostname or failed connection stops the command before Linux live tests.
   Print and save previous paths plus manual recovery commands under
   `${XDG_STATE_HOME:-~/.local/state}/nix-config/deploy/before-*.txt`.
4. If enabled, use `ssh -t` to run **`nh darwin build --no-nom` on the Mac** for
   that exact published revision and `-H H952L3DPHH`, refusing lock updates.
   This builds without activating; failure stops before Linux live tests. The
   Mac cannot be checked by building its aarch64-darwin closure on Linux.
5. Run upstream `deploy --test` against discovery, then endeavour, using the
   built snapshot. Closures are copied over SSH and each Linux host runs
   `switch-to-configuration test`. **This changes running services now.**
   Darwin has no equivalent `--test` and is never in this loop.
6. After the Linux tests succeed, stop at the single **`[y/N]`** gate. Inspect
   services before answering. Only Yes runs the Linux `deploy` switches for the
   tested snapshot, updating boot loaders, followed by the Mac's **TTY-backed
   `nh darwin switch --no-nom`**, for the same published revision. Enter the Mac's
   password when sudo/Homebrew asks; no password is stored or forwarded by the
   wrapper. There is no `--yes` mode.

The Mac switch runs only after **both** Linux switches succeed. If it fails or
loses SSH after that point, the command exits nonzero and explicitly reports that
Linux switches remain applied. It does **not** attempt a cross-platform rollback.
An unreachable/unready Mac stops early with an explicit `--no-mac` suggestion;
there is no silent skip.

The wrapper uses `--skip-checks` on the two upstream invocations only because
it already built the four deploy-specific checks. It does not replace the
repository's other `nix flake check` checks. All phases refuse lock-file updates;
checkout edits made while checking services cannot change the tested generation.

Linux builds use endeavour's caches and credentials. The Linux targets do not
need access to the private flake sources for normal deploys. `remoteBuild = false` avoids
asking weaker machines to compile the full desktop closure. With
`fastConnection` left at its upstream default, targets can substitute cached
paths before copying the remaining closure.

## Mac transport, source pinning, and recovery

Jordan chose to keep the managed work Mac out of deploy-rs. It is **not** in
`deploy.nodes`, the Linux activation checks, or their `--test` loop. The controller
runs two ordinary SSH commands: a remote build before the approval gate, then a
remote switch after Yes and the Linux switches. Both use `ssh -t`; the existing
password-required sudo policy stays unchanged. There is no NOPASSWD grant, root
SSH, agent forwarding, sudo-password pipe, or extra Nix trust grant for the Mac.

The Mac's config uses Determinate Nix (`nix.enable = false`). Its Homebrew
activation enables auto-update/upgrade and has many casks; nested installers may
ask for sudo or GUI interaction. A real TTY allows attended password prompts,
but does not promise that every MDM/GUI installer can finish over SSH. Homebrew
changes are mutable and are **not** undone by a Nix generation rollback. Nothing
in this change disables Homebrew or changes Mosyle/PAM policy.

The immutable ref is:

```text
git+ssh://git@github.com/jordangarrison/nix-config?allRefs=1&rev=<40-character-SHA>
```

Both remote `nh darwin` calls explicitly select `-H H952L3DPHH`, pass `--no-nom`,
and refuse lock updates. The controller verifies the revision is fetchable from
the canonical remote and matches its clean snapshot before any target preflight.
The Mac has its own GitHub SSH access to the private inputs. Neither its checkout
(`~/dev/jordangarrison/nix-config`) nor its branch is changed, pulled, or reset.
Commit and **push** before a full fleet deployment; use `--no-mac` for dirty or
local-only Linux work. Cached copies of a previously published immutable ref are
valid; the controller requests refreshed metadata rather than trusting a local
branch/upstream label alone.

The Mac preflight records its resolved `/run/current-system` and a manual
`sudo env HOME=/var/root /nix/store/<previous-darwin-system>/activate` recovery command. No automatic
Mac rollback is promised by this SSH/nh path. If recovery is required, obtain
approval, reactivate the recorded old closure in a local or TTY-backed terminal,
and separately restore `/nix/var/nix/profiles/system` with `sudo nix-env --profile
/nix/var/nix/profiles/system --set <previous-darwin-system>` if necessary. Neither
step reverses Homebrew updates or service-data changes. Preserve recovery access.

Only read-only Mac SSH checks were performed while implementing this draft. The
remote build and switch path is covered with mocks, **not validated on the Mac**;
the first real remote build/activation remains a separately approved operator task.

## Linux SSH, sudo, and one-time bootstrap

No new root SSH login, public key, firewall rule, or secret is introduced.
The existing Linux Jordan user has `NOPASSWD` sudo. The draft sets:

- `sshUser = "jordangarrison"`, profile `user = "root"`;
- `sudo = "sudo -n -u"`, `interactiveSudo = false`;
- batch-mode SSH with strict host-key checks, a 10-second connect timeout,
  and bounded keepalives;
- `nix.settings.trusted-users = [ "root" "jordangarrison" ]` **only** on
  endeavour and discovery, via `modules/nixos/deploy-target.nix`.

Nix trust is root-equivalent. Jordan explicitly approved this host-scoped grant;
he already has unrestricted sudo. It is needed because an ordinary, untrusted
SSH user cannot import locally built unsigned store paths, even when activation
will later use sudo. Do not disable signature checks globally or add all of
`@wheel` to work around this.

Read-only checks during drafting confirmed SSH to `localhost` and `discovery`,
the expected hostnames, and passwordless sudo. Both running Nix daemons currently
trust only `root`. **This PR cannot bootstrap its own first unsigned SSH copy.**
Before the first fleet deployment, Jordan must apply the trust change on each
host through the normal approved **build → test → switch** flow, using a checkout
with private-input access. On each target, select that host explicitly:

```bash
# HOST is endeavour or discovery, matching the machine running these commands.
nh os build . -H "$HOST" --no-nom
nh os test . -H "$HOST" --no-nom
# Inspect services, then obtain Jordan's explicit approval:
nh os switch . -H "$HOST" --no-nom
```

This bootstrap is a real system activation, not a read-only prerequisite. If a
checkout/private-input access is unavailable on discovery, plan an approved
root import of the locally built closure instead; do not improvise remote writes
from an agent session. SSH keys and known-host entries must already be present.
Use `ssh -o BatchMode=yes -o StrictHostKeyChecking=yes discovery true` and the
same command for localhost to check that without changing the hosts.

## Rollback limits: read before the first deployment

Both `autoRollback` and `magicRollback` are enabled. Activation may take up to
600 seconds; the confirmation window is 60 seconds. Upstream reconnects after
activation and confirms it; if it cannot confirm, the remote rollback mechanism
attempts recovery. A failed multi-target deployment also attempts to revoke
already-successful targets. These are best-effort system-generation rollbacks,
not service health checks, database backups, or transactions across machines.

**Upstream `deploy --test` is not identical to `nh os test`:** it also sets
`/nix/var/nix/profiles/system` before invoking the NixOS test activation, although
it does not update the boot loader. Jordan approved using this behavior in the
guarded command. Therefore:

- Answering No, EOF, or interrupting at the final prompt **does not undo** live
  tests or restore the profile link. The old boot-loader entry remains until a
  switch, but the system-profile link may already point at the tested generation.
- After a successful test, a switch-phase rollback may select the **tested**
  generation rather than the generation from before the command started.
- On the very first deploy-rs activation, the previous plain NixOS generation
  may lack `deploy-rs-activate`. Upstream's attempt to reactivate it can fail.
- SSH reachability is not proof that application services work. Inspect them
  before confirming the switch. Keep console/Tailscale recovery access and
  service-data backups available.

Use the printed pre-test store paths for manual recovery if needed. On the
relevant host, with Jordan's approval, run the recorded command:

```bash
sudo /nix/store/<previous-nixos-system>/bin/switch-to-configuration switch
```

This restores running services and boot configuration, but does **not** reset
`/nix/var/nix/profiles/system`. If deploy-rs changed that link, restore it to the
recorded plain system closure as a separate, approved recovery action:

```bash
sudo nix-env --profile /nix/var/nix/profiles/system --set /nix/store/<previous-nixos-system>
```

Do not garbage-collect old systems during a deployment/recovery window. Do not
assume rollback can undo database migrations or application state changes.

## Inspiration

Inspired by [MichaelVessia/nixos-config](https://github.com/MichaelVessia/nixos-config),
particularly its [`deploy` output](https://github.com/MichaelVessia/nixos-config/blob/8b73488f01dd758f476e0af38b9ffb22c5a13262/flake.nix#L244-L273)
and [`fleet` script](https://github.com/MichaelVessia/nixos-config/blob/8b73488f01dd758f476e0af38b9ffb22c5a13262/scripts/nixos/fleet).
Borrowed: a small explicit fleet, ordinary flake activation helpers, one command.
Not copied: root SSH, target-side builds, a separate local reload, skipped deploy
validation, or per-controller groups (this draft has one controller).

The deploy-rs flake is locked in `flake.lock`; its nixpkgs input follows this
repository. Upstream sources:
[README](https://github.com/serokell/deploy-rs/blob/1cec0527bd09074bbee6d4461900ce5d58267217/README.md),
[test/profile behavior](https://github.com/serokell/deploy-rs/blob/1cec0527bd09074bbee6d4461900ce5d58267217/src/bin/activate.rs#L650-L715).
