#!/usr/bin/env bash
# Window switcher using hyprctl + rofi
# Windows sorted by focus history (most recent first), excluding current window

# Build window list: "Title [App]" with address stored separately
mapfile -t windows < <(hyprctl clients -j | jq -r '
  sort_by(.focusHistoryID) |
  .[] |
  select(.mapped == true and .focusHistoryID > 0) |
  (.class |
    if test("org.wezfurlong.wezterm") then "WezTerm"
    elif test("^brave-browser$") then "Brave"
    elif test("^brave-") then "Brave App"
    elif test("^Emacs$") then "Emacs"
    elif test("^Slack$") then "Slack"
    else . end
  ) as $app |
  "\(.address)\t\(.title)  [\($app)]"
')

# Extract just display text for rofi
display=""
for entry in "${windows[@]}"; do
  display+="${entry#*$'\t'}"$'\n'
done

# Show rofi and get selection index
choice=$(echo -n "$display" | rofi -dmenu -p "Switch" -i -format i -selected-row 0)

# Focus selected window
if [ -n "$choice" ] && [ "$choice" -ge 0 ] 2>/dev/null; then
  addr=$(echo "${windows[$choice]}" | cut -f1)
  hyprctl dispatch focuswindow "address:$addr"
fi
