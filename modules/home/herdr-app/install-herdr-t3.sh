# Install the Herdr T3 layout (github:JinJieBeWater/herdr-t3) into a Herdr app home.
# Usage: install-herdr-t3 <source> <app home>
#
# Real copies, not Nix symlinks: the mods import ./name.js and load their own
# SVGs, which the app refuses through a symlink into the store. The app also
# writes the layout file (theme picker, sidebar stack, focus ring color), so
# keep those values across installs, as upstream scripts/sync.sh does.
set -euo pipefail

src=$1
app=$2

mkdir -p "$app/mods" "$app/layouts"

# One mod at a time; other mods are left alone. Excluded files are written
# by the app and are protected from --delete.
for d in "$src"/mods/t3-*/; do
  rsync -a --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
    --exclude gpui-kit.d.ts --exclude herdr.d.ts --exclude jsconfig.json \
    "$d" "$app/mods/$(basename "$d")/"
done

install -m 644 "$src/layouts/herdr-t3.svg" "$app/layouts/herdr-t3.svg"

layout="$app/layouts/herdr-t3.json"
old=$(cat "$layout" 2>/dev/null || echo '{}')
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --argjson old "$old" '[$old | .. | objects | .focus? | objects | .color][0] as $c
  | ([$old | .. | objects | select((.id | strings) and .active) | {(.id): .active}] | add // {}) as $active
  | (if $old.theme then .theme = $old.theme else . end)
  | (.. | objects | select((.id | strings) and $active[.id])) |= (.active = $active[.id])
  | (.. | objects | .focus? | objects | .color) |= ($c // .)' \
  "$src/layouts/herdr-t3.json" >"$tmp"

# Write only on change: every save reloads the layout.
if ! cmp -s "$tmp" "$layout"; then
  install -m 644 "$tmp" "$layout"
fi
