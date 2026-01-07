#!/usr/bin/env bash
# Clipboard history picker using cliphist + rofi

cliphist list | rofi -dmenu -p "Clipboard" | cliphist decode | wl-copy
