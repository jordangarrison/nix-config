#!/usr/bin/env bash
# herdr-handoff — migrate the running herdr session onto the current binary,
# keeping live pane processes alive. The Nix-viable alternative to
# `herdr update --handoff` (whose downloader can't write to /nix/store).
#
# Usage: after `nh os switch`, run `herdr-handoff` to hand the running
# server's live panes to the freshly-built herdr binary.
set -euo pipefail

new_exe="$(readlink -f "$(command -v herdr)")"
echo "herdr-handoff: handing off live panes to ${new_exe}"
echo "herdr-handoff: if the protocol is incompatible, herdr will refuse and you should restart instead."
exec herdr server live-handoff --import-exe "${new_exe}"
