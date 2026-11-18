# Hex dictation on macOS

`default.nix` pins the signed, notarized upstream Apple silicon release. It
copies `Hex.app` without fixups or re-signing, so macOS can keep recognizing
Anomaly's signing identity across rebuilds and releases. It requires macOS 15
or later. This is not nixpkgs' `hex` hex dump utility.

Only `users/jordangarrison/home-darwin.nix` installs this package. Home Manager's
existing `copyApps` installs a real, writable bundle at:

```text
~/Applications/Home Manager Apps/Hex.app
```

The package also exposes the bundled `hex` CLI on PATH. No Linux host imports
this package, and no model or runtime settings are managed by Nix.

## First run, after an approved switch

1. Open **Hex** from Spotlight or the app folder above. Do not run the GUI from
   the Nix store: that is not the copy whose permissions you want to grant.
2. Follow onboarding. Allow **Microphone** access and enable Hex under
   **System Settings → Privacy & Security → Accessibility**. Use the copied
   app above if macOS asks you to locate it. Restart Hex if prompted.
3. Let Hex download its speech model. Transcription runs locally after the
   download; choose another model in Settings if needed. No models are vendored.
4. Default dictation: **hold Option, speak, release** to paste at the cursor.
   Settings can change the shortcut or use tap-to-toggle mode. Avoid conflicts
   with Superwhisper or another dictation app; this config does not remove them.
   **Option-Shift-V** pastes the last dictation again.

Upstream's dictation onboarding requests Microphone and Accessibility, not a
separate Input Monitoring grant. Optional features can request more permissions
(for example screen/audio capture or Automation); grant only what you use.

## Updates and rollback

Hex v3.4.0 has its own signed-bundle updater (not Sparkle). It can replace the
writable Home Manager copy. **The next Home Manager activation restores the
Nix-pinned version**, even if Hex updated itself. Quit Hex before switching so
the running process does not keep using the previous bundle.

The `hex` CLI points into the immutable Nix package, so it stays at the pinned
version even if the GUI copy updates. Prefer updating through Nix to keep them
aligned. Hex supports the `DisableUpdates` boolean in the `anomaly.hex` macOS
defaults domain if an administrator needs to turn off its updater; this package
does not change that preference.

To update the declarative release:

1. Set `version` in `default.nix` and add the release ZIP hash to `hashes`.
   Unknown versions fail evaluation with an instruction to add the hash.
2. Read the ZIP digest from the [GitHub release assets][releases] or run
   `nix store prefetch-file` against its versioned URL. Convert the SHA256 to SRI
   with `nix hash convert --hash-algo sha256 --to sri <sha256>`.
3. Run the eval test in `tests/hex-darwin.nix` (update its expected pin), then
   `nh darwin build . --no-nom`. Verify the built app's signature with
   `/usr/bin/codesign --verify --deep --strict <store-path>/Applications/Hex.app`.
4. Ask before applying a switch. A Nix rollback restores the package version,
   not Hex's downloaded models, settings, or history.

## Sources

- [Upstream releases][releases] (v3.4.0 ZIP digest:
  `1ab0242dc3bb011c88568903cbf1e9d30310867a46f5168309853d6f8b4ca650`)
- [macOS release signing and notarization][signing]
- [macOS updater and DisableUpdates policy][updater]
- [First-run permission state][onboarding]
- [Upstream usage and model downloads][usage]

[releases]: https://github.com/anomalyco/hex/releases/tag/v3.4.0
[signing]: https://github.com/anomalyco/hex/blob/v3.4.0/.github/release/sign-macos.sh
[updater]: https://github.com/anomalyco/hex/blob/v3.4.0/src/updater/macos.rs
[onboarding]: https://github.com/anomalyco/hex/blob/v3.4.0/src/desktop/onboarding.rs
[usage]: https://github.com/anomalyco/hex/blob/v3.4.0/README.md
