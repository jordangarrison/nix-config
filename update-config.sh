#!/usr/bin/env bash

# Set a flag for $DRY_RUN
DRY_RUN=false
# Read in the command line arguments and set the $DRY_RUN flag
while getopts ":d" opt; do
  case $opt in
  d)
    DRY_RUN=true
    shift
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    exit 1
    ;;
  esac
done

# select the correct config file
SELECTION=${1:-workstation}
SCRIPTPATH="$(
  cd "$(dirname "$0")"
  pwd -P
)"
CONFIG_DIR="$SCRIPTPATH"/"$SELECTION"
echo "$CONFIG_DIR"

# update the config
sed -f "$CONFIG_DIR"/.env.sed "$CONFIG_DIR"/configuration.nix >"$CONFIG_DIR"/.tmp.configuration.nix

# copy new file to /etc/nixos unless $DRY_RUN is set
if [ -z "$DRY_RUN" ]; then
  # copy old file to tmp
  mkdir -p "$SCRIPTPATH"/.tmp
  cp /etc/nixos/configuration.nix "${SCRIPTPATH}/.tmp/configuration-backup-$(date +'%F-%H%M%S').nix"

  sudo cp $CONFIG_DIR/.tmp.configuration.nix /etc/nixos/configuration.nix
else
  echo "Dry run, not copying new configuration to /etc/nixos"
fi
