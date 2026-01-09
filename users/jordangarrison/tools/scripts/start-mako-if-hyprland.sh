#!/usr/bin/env bash
# Start mako only if running Hyprland
# This allows multi-desktop setups without notification daemon conflicts

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ]; then
    exec mako
fi
