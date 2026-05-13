{ ... }:

{
  # Patch upstream Brave (binary tarball repackaged by nixpkgs) so the Web
  # Speech API actually works on NixOS. Three things are needed:
  #   1. speechd-minimal in LD_LIBRARY_PATH so dlopen("libspeechd.so.2") finds
  #      it (mirroring what nixpkgs already does for Firefox).
  #   2. --enable-speech-dispatcher on the command line — Chromium-based
  #      browsers gate the speechd code path behind this switch and do nothing
  #      without it (which is why dlopen never even fires).
  #   3. A managed-policy file suppressing Chromium's "bad flags" infobar,
  #      which would otherwise warn the user about #2 on every launch.
  # Tracked upstream in NixOS/nixpkgs#41074.
  #
  # SECURITY CAVEATS — read before copying this to a different machine.
  # The above changes weaken Brave's security posture in ways the upstream
  # Chromium project considers material. Specifically:
  #
  #   • --enable-speech-dispatcher pulls libspeechd.so.2, the speech-dispatcher
  #     daemon, and its output modules (espeak-ng, pico, flite) into the
  #     attack surface of any web page that can reach the SpeechSynthesis API.
  #     None of these are sandboxed the way Chromium's first-party media
  #     services are; vulnerabilities in their text/SSML parsing or IPC become
  #     reachable from JavaScript. This is exactly why Chromium leaves the
  #     flag off by default and labels it "bad".
  #
  #   • CommandLineFlagSecurityWarningsEnabled=false suppresses the infobar
  #     Chromium uses to tell users their browser is running in a non-default
  #     security state. Suppressing it means a future maintainer (or a
  #     compromised auto-launcher) could slip in *additional* risky flags
  #     without anyone noticing the visual warning that would normally fire.
  #
  #   • LD_LIBRARY_PATH gains speech-dispatcher's lib dir. Negligible on its
  #     own, but worth knowing.
  #
  # Mitigating context: speech-dispatcher runs as the unprivileged user on a
  # local Unix socket, and this is the same configuration most desktop Linux
  # distros (Ubuntu, Fedora) ship by default — the incremental risk over a
  # stock Linux desktop is small. The risk over stock NixOS is real, however,
  # because NixOS does *not* ship speechd by default.
  #
  # Apply this only on single-user trusted machines where the Web Speech API
  # is actually needed. Do not apply to multi-tenant hosts, kiosks exposed
  # to the public internet, or systems running untrusted code.
  nixpkgs.overlays = [
    (final: prev: {
      brave = prev.brave.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ final.speechd-minimal ];
        preFixup = (old.preFixup or "") + ''
          gappsWrapperArgs+=(
            --prefix LD_LIBRARY_PATH : ${final.lib.makeLibraryPath [ final.speechd-minimal ]}
            --add-flags "--enable-speech-dispatcher"
          )
        '';
      });
    })
  ];

  environment.etc."brave/policies/managed/disable-bad-flag-warnings.json".text = builtins.toJSON {
    CommandLineFlagSecurityWarningsEnabled = false;
  };
}
