#!/usr/bin/env bash

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
SECRET_DIR="$SCRIPTPATH"/.secrets
echo "$CONFIG_DIR"

# copy old file to tmp
mkdir -p "$SCRIPTPATH"/.tmp
cp $CONFIG_DIR/.tmp.configuration.nix "${SCRIPTPATH}/.tmp/configuration-backup-$(date +'%F-%H%M%S').nix"
# update the config
sed -f "$SECRET_DIR"/"${SELECTION}.sed" "$CONFIG_DIR"/configuration.nix >"$CONFIG_DIR"/.tmp.configuration.nix

# copy new file to /etc/nixos unless $DRY_RUN is set
if [ -z "$DRY_RUN" ]; then

  sudo nixos-rebuild switch -I nixos-config=$CONFIG_DIR/.tmp.configuration.nix
else
  echo "Dry run, not copying new configuration to /etc/nixos"
fi
