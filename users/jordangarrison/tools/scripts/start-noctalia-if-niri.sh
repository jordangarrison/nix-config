#!/usr/bin/env bash
# Start noctalia-shell only if running Niri
# This allows multi-desktop setups without notification daemon conflicts

if [ "$XDG_CURRENT_DESKTOP" = "niri" ]; then
    exec noctalia-shell
fi
