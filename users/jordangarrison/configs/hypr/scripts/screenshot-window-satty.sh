#!/usr/bin/env bash
# Active window screenshot with Satty annotation
# Uses niri msg to get focused window geometry, then grim to capture that region
WINDOW=$(niri msg -j focused-window | jq -r '"\(.x),\(.y) \(.width)x\(.height)"')
grim -g "$WINDOW" -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
