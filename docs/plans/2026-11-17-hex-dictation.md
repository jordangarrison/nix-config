# Hex dictation on the Mac — implementation plan

**Goal:** Install Hex on `H952L3DPHH` through Nix, without applying a switch.

**Approved design:** Package the signed, notarized upstream v3.4.0 ZIP in
`packages/hex-bin/default.nix`. Pin its hash and skip fixups so the bundle's
signature stays intact. Add it only to `users/jordangarrison/home-darwin.nix`;
existing Home Manager `copyApps` puts it in
`~/Applications/Home Manager Apps/Hex.app`.

**Alternatives checked:** Upstream's flake has Linux outputs only. The pinned
nixpkgs `hex` is a different program (a hex dump tool). The official Homebrew
cask preserves the signature but follows the latest release; this host upgrades
casks during activation. The Nix package makes the starting version explicit.

**Tech stack:** Nix, nix-darwin, Home Manager, upstream macOS app bundle.

## 1. Test the installation contract first

Create `tests/hex-darwin.nix` and run:

```sh
nix eval --json --impure --expr 'import ./tests/hex-darwin.nix { flake = builtins.getFlake (toString ./.); }'
```

Check that the Mac home includes Hex with `dontFixup`, an explicit release URL,
a version hash, and arm64 Darwin scope; also check that unknown versions fail
and that the app is copied rather than linked. Run before implementation to
observe the missing-package failure, then again after implementation.

## 2. Package and wire the signed bundle

Create `packages/hex-bin/default.nix`, with a hash table and a clear error for
an unknown version. Unpack the ZIP and copy `Hex.app` without modifying code.
Expose the bundled `hex` CLI. Add the package to the Mac home only; do not add
an overlay or flake input. Document setup and update behavior in
`packages/hex-bin/README.md`.

## 3. Validate and submit

- Build the package; verify its signature, team, bundle ID, and version without
  launching it. Confirm the published ZIP SHA256.
- Run `nh darwin build . --no-nom`. Do not switch or grant permissions.
- Linux validation is delegated to main on endeavour after push. The baseline
  Mac evaluation already fails on private Forgejo input SSH authentication;
  main approved skipping it here. Do not change SSH configuration.
- Review the diff, commit, push normally, and open a PR against `main`.

## Update and first-run contract

Hex's own updater can replace the writable copy. A later Home Manager activation
restores the pinned release. Nix updates change the package version and add that
release's SHA256 to the table. First run downloads a model; models and runtime
state are not managed here. Jordan grants Microphone and Accessibility access
and chooses a shortcut; default dictation is hold Option, speak, release.
