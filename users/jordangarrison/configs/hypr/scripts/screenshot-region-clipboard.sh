#!/usr/bin/env bash
# Region screenshot to clipboard
grim -g "$(slurp)" - | wl-copy
