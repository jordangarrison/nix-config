#!/usr/bin/env bash
# Keybinds Help - Display all Hyprland keybindings dynamically

# Parse and format keybindings from hyprctl
parse_bindings() {
  hyprctl -j binds |
    jq -r '.[] | {modmask, key, description, dispatcher, arg} | "\(.modmask),\(.key),\(.description),\(.dispatcher),\(.arg)"' |
    sed -r \
      -e 's/null//' \
      -e 's/^0,/,/' \
      -e 's/^1,/SHIFT + /' \
      -e 's/^4,/CTRL + /' \
      -e 's/^5,/SHIFT + CTRL + /' \
      -e 's/^8,/ALT + /' \
      -e 's/^64,/SUPER + /' \
      -e 's/^65,/SUPER + SHIFT + /' \
      -e 's/^68,/SUPER + CTRL + /' \
      -e 's/^72,/SUPER + ALT + /' \
      -e 's/^76,/SUPER + CTRL + ALT + /' |
    awk -F, '
    {
      key_combo = $1 $2
      gsub(/^[ \t]*\+?[ \t]*/, "", key_combo)

      # Use description if available, otherwise use dispatcher + arg
      if ($3 != "") {
        action = $3
      } else {
        action = $4
        if ($5 != "") action = action " " $5
      }

      # Clean up action
      gsub(/exec /, "", action)
      gsub(/~\/dev\/jordangarrison\/nix-config\/users\/jordangarrison\/configs\/hypr\/scripts\//, "", action)

      if (action != "" && key_combo != "") {
        printf "%-30s → %s\n", key_combo, action
      }
    }'
}

parse_bindings | rofi -dmenu -p "Keybindings" -i
