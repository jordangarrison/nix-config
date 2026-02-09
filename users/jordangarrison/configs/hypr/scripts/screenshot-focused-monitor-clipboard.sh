#!/usr/bin/env bash
# Focused monitor screenshot to clipboard
FOCUSED=$(niri msg -j focused-output | jq -r '.name')
grim -o "$FOCUSED" - | wl-copy
