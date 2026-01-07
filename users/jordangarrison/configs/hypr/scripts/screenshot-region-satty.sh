#!/usr/bin/env bash
# Region screenshot with Satty annotation
grim -g "$(slurp)" -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
