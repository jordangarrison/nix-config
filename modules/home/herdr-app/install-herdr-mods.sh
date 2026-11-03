# Copy third-party Herdr mods into a Herdr app home.
# Usage: install-herdr-mods <app home> <name>=<mod folder>...
#
# Real copies, not Nix symlinks: these mods import ./name.js or load their own
# files, which the app refuses through a symlink into the store (see
# install-herdr-t3.sh). Each named mod folder is owned by this step: local
# edits are replaced. Files the app writes are excluded and kept.
set -euo pipefail

app=$1
shift

mkdir -p "$app/mods"

for spec in "$@"; do
  name=${spec%%=*}
  src=${spec#*=}
  dest="$app/mods/$name"
  # Older generations linked these files; drop the links so rsync writes files.
  if [ -d "$dest" ]; then
    find "$dest" -type l -lname '/nix/store/*' -delete
  fi
  rsync -a --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
    --exclude gpui-kit.d.ts --exclude herdr.d.ts --exclude jsconfig.json \
    "$src/" "$dest/"
done
