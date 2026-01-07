#!/usr/bin/env bash
# Full screen screenshot with Satty annotation
grim -t ppm - | satty --filename - --output-filename ~/Pictures/Screenshots/$(date '+%Y%m%d-%H%M%S').png
