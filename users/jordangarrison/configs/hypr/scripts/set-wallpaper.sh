#!/usr/bin/env bash
# Set wallpaper via hyprctl hyprpaper
# Usage: set-wallpaper.sh <wallpaper_path>

WALLPAPER="$1"

if [ -z "$WALLPAPER" ]; then
    echo "Usage: set-wallpaper.sh <wallpaper_path>"
    exit 1
fi

# Get connected monitors and set wallpaper for each
for monitor in $(hyprctl monitors -j | jq -r '.[].name'); do
    hyprctl hyprpaper wallpaper "$monitor,$WALLPAPER"
done

echo "Wallpaper set to: $WALLPAPER"
