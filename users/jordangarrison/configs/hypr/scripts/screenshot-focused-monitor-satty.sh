#!/usr/bin/env bash
# Focused monitor screenshot with Satty annotation
# Uses niri msg to get focused output, then grim to capture just that output
FOCUSED=$(niri msg -j focused-output | jq -r '.name')
grim -o "$FOCUSED" -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
